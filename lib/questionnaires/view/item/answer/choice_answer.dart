import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:fhir/r4.dart';
import 'package:flutter/material.dart';

import '../../../../fhir_types/fhir_types_extensions.dart';
import '../../../../logging/logging.dart';
import '../../../../questionnaires/model/questionnaire_extensions.dart';
import '../../../questionnaires.dart';
import '../../broken_questionnaire_item.dart';
import '../../xhtml.dart';

class ChoiceAnswer extends QuestionnaireAnswerFiller {
  static final logger = Logger(ChoiceAnswer);
  // This class uses CodeableConcept to model multiple choice and open choice.

  const ChoiceAnswer(
      QuestionnaireLocation location, AnswerLocation answerLocation,
      {Key? key})
      : super(location, answerLocation, key: key);
  @override
  State<StatefulWidget> createState() => _ChoiceAnswerState();
}

class _ChoiceAnswerState
    extends QuestionnaireAnswerState<CodeableConcept, ChoiceAnswer> {
  static final logger = Logger(_ChoiceAnswerState);
  // ignore: prefer_collection_literals
  final _answerOptions = LinkedHashMap<String, QuestionnaireAnswerOption>();
  Object? _initFailure;

  _ChoiceAnswerState();

  @override
  void initState() {
    super.initState();

    try {
      _createAnswerOptions();

      if (widget.location.responseItem != null) {
        initialValue = CodeableConcept(
            coding: widget.location.responseItem!.answer
                ?.map((answer) =>
                    _answerOptions[_choiceStringFromCoding(answer.valueCoding)]!
                        .valueCoding!)
                .toList());
      }
    } catch (exception) {
      logger.log(
          'Could not initialize ChoiceAnswer for ${widget.location.linkId}',
          error: exception);
      _initFailure = exception;
    }
  }

  @override
  QuestionnaireResponseAnswer? fillAnswer() {
    throw UnsupportedError('Choice Answer will always return choice answers.');
  }

  @override
  List<QuestionnaireResponseAnswer>? fillChoiceAnswers() {
    if (value == null) {
      return null;
    }

    // TODO(tiloc): Return the order of the codings in the order of the choices
    // TODO(tiloc): Support open free text (should always come last?)
    final result = value!.coding?.map<QuestionnaireResponseAnswer>((coding) {
      // Some answers may only be a display, not have a code
      return coding.code != null
          ? QuestionnaireResponseAnswer(
              valueCoding:
                  _answerOptions[_choiceStringFromCoding(coding)]!.valueCoding)
          : QuestionnaireResponseAnswer(valueCoding: coding);
    }).toList();

    return result;
  }

  @override
  bool hasChoiceAnswers() {
    return true;
  }

  @override
  Widget buildReadOnly(BuildContext context) {
    return (_initFailure == null)
        ? Text(value?.localizedDisplay(Localizations.localeOf(context)) ?? '-')
        : BrokenQuestionnaireItem.fromException(_initFailure!);
  }

  @override
  Widget buildEditable(BuildContext context) {
    if (_initFailure != null) {
      return BrokenQuestionnaireItem.fromException(_initFailure!);
    }

    try {
      if (!(widget.location.questionnaireItem.repeats == Boolean(true)) &&
          (_answerOptions.length > 10 ||
              widget.location.questionnaireItem
                  .isItemControl('autocomplete'))) {
        return _buildLookupAnswers(context);
      } else {
        return _buildChoiceAnswers(context);
      }
    } catch (exception) {
      return BrokenQuestionnaireItem.fromException(exception);
    }
  }

  CodeableConcept? _fillValue(String? newValue) {
    return (newValue != null)
        ? CodeableConcept(coding: [_answerOptions[newValue]!.valueCoding!])
        : null;
  }

  bool _isExclusive(Coding coding) {
    return _answerOptions[_choiceStringFromCoding(coding)]!
            .extension_
            ?.extensionOrNull(
                'http://hl7.org/fhir/StructureDefinition/questionnaire-optionExclusive')
            ?.valueBoolean
            ?.value ==
        true;
  }

  /// Turn on/off the checkbox with the provided [toggleValue].
  /// Used in repeating items.
  CodeableConcept? _fillToggledValue(String? toggleValue) {
    logger.log('Enter fillToggledValue $toggleValue', level: LogLevel.trace);
    if (toggleValue == null) {
      return null;
    }
    if ((value == null) || (value!.coding == null)) {
      return _fillValue(toggleValue);
    }

    final entryIndex = value!.coding!
        .indexWhere((coding) => coding.code?.value == toggleValue);
    if (entryIndex == -1) {
      logger.log('$toggleValue currently not selected.', level: LogLevel.debug);
      final enabledCodeableConcept = _fillValue(toggleValue)!;
      final enabledCoding = enabledCodeableConcept.coding!.first;
      if (_isExclusive(enabledCoding)) {
        logger.log('$toggleValue isExclusive', level: LogLevel.debug);
        // The newly enabled checkbox is exclusive, kill all others.
        return enabledCodeableConcept;
      } else {
        logger.log('$toggleValue is not exclusive', level: LogLevel.debug);
        // Kill all exclusive ones.
        return value!.copyWith(coding: [
          ...value!.coding!.whereNot((coding) => _isExclusive(coding)),
          enabledCoding
        ]);
      }
    } else {
      logger.log('$toggleValue currently selected.', level: LogLevel.debug);
      return CodeableConcept(coding: value!.coding!..removeAt(entryIndex));
    }
  }

  // Take the existing extensions that might contain information about
  // ordinal values and convert them from ordinalValue to iso21090-CO-value
  List<FhirExtension>? _createOrdinalExtension(
      List<FhirExtension>? inExtension) {
    List<FhirExtension>? responseOrdinalExtension;

    final FhirExtension? ordinalExtension = inExtension?.extensionOrNull(
        'http://hl7.org/fhir/StructureDefinition/ordinalValue');
    if (ordinalExtension != null) {
      responseOrdinalExtension = <FhirExtension>[
        FhirExtension(
            url: FhirUri(
                'http://hl7.org/fhir/StructureDefinition/iso21090-CO-value'),
            valueDecimal: ordinalExtension.valueDecimal),
      ];
    }

    return responseOrdinalExtension;
  }

  List<FhirExtension>? _createOptionPrefixExtension(
      List<FhirExtension>? inExtension) {
    List<FhirExtension>? responseOptionPrefixExtension;

    final FhirExtension? labelExtension = inExtension?.extensionOrNull(
        'http://hl7.org/fhir/StructureDefinition/valueset-label');
    if (labelExtension != null) {
      responseOptionPrefixExtension = <FhirExtension>[
        FhirExtension(
            url: FhirUri(
                'http://hl7.org/fhir/StructureDefinition/questionnaire-optionPrefix'),
            valueString: labelExtension.valueString),
      ];
    }

    return responseOptionPrefixExtension;
  }

  String? _choiceStringFromCoding(Coding? coding) {
    if (coding == null) {
      return null;
    }
    final choiceString =
        (coding.code != null) ? coding.code?.value : coding.display;

    if (choiceString == null) {
      throw QuestionnaireFormatException(
          'Insufficient info for choice string in $coding', coding);
    } else {
      return choiceString;
    }
  }

  String? _choiceStringFromCodings(List<Coding>? codings) {
    if (codings == null) {
      return null;
    }

    final coding = codings.firstOrNull;
    return _choiceStringFromCoding(coding);
  }

  /// Extract a string from a [CodeableConcept].
  /// Can be used as groupValue in checkboxes/radiobuttons, or as a key in maps
  /// Throws when Questionnaire is malformed.
  /// Returns null if [codeableConcept] is null
  String? _choiceString(CodeableConcept? codeableConcept) {
    if (codeableConcept == null) {
      return null;
    }
    return _choiceStringFromCodings(
        ArgumentError.checkNotNull(codeableConcept.coding));
  }

  void _addAnswerOption(Coding coding) {
    _answerOptions.addEntries([
      MapEntry<String, QuestionnaireAnswerOption>(
          coding.code!.toString(),
          FDashQuestionnaireAnswerOptionExtensions.fromCoding(
            coding,
            extensionBuilder: (inCoding) =>
                _createOptionPrefixExtension(inCoding.extension_),
            codingExtensionBuilder: (inCoding) =>
                _createOrdinalExtension(inCoding.extension_),
          ))
    ]);
  }

  /// Convert [ValueSet]s or [QuestionnaireAnswerOption]s to normalized [QuestionnaireAnswerOption]s
  void _createAnswerOptions() {
    final qi = widget.location.questionnaireItem;

    if (qi.answerValueSet != null) {
      final key = qi.answerValueSet?.value?.toString();
      if (key == null) {
        throw QuestionnaireFormatException(
            'Questionnaire choice item does not specify a key', qi);
      }

      widget.location.top.visitValueSet(key, _addAnswerOption, context: qi);
    } else {
      if (qi.answerOption != null) {
        _answerOptions.addEntries(qi.answerOption!.map<
            MapEntry<String, QuestionnaireAnswerOption>>((qao) => MapEntry<
                String, QuestionnaireAnswerOption>(
            qao.optionCode,
            qao.copyWith(
                valueCoding: (qao.valueCoding != null)
                    ? qao.valueCoding!.copyWith(
                        userSelected: Boolean(true),
                        extension_: _createOrdinalExtension(qao.extension_))
                    : Coding(
                        // The spec only allows valueCoding, but real-world incl. valueString
                        display: qao.valueString,
                        userSelected: Boolean(true))))));
      }
    }
  }

  Widget _buildChoiceAnswers(BuildContext context) {
    final qi = widget.location.questionnaireItem;
    final isCheckBox = qi.isItemControl('check-box');
    final isMultipleChoice = (qi.repeats?.value ?? isCheckBox) == true;

    final choices = <Widget>[];
    if (!isMultipleChoice) {
      choices.add(RadioListTile<String?>(
          title: Text(
            '---',
            style: Theme.of(context).textTheme.bodyText2,
          ),
          value: null,
          groupValue: _choiceString(value),
          onChanged: (String? newValue) {
            value = _fillValue(newValue);
          }));
    }
    for (final choice in _answerOptions.values) {
      final optionPrefix = choice.extension_
          ?.extensionOrNull(
              'http://hl7.org/fhir/StructureDefinition/questionnaire-optionPrefix')
          ?.valueString;
      final optionPrefixDisplay =
          (optionPrefix != null) ? '$optionPrefix ' : '';
      final optionTitle =
          '$optionPrefixDisplay${choice.localizedDisplay(Localizations.localeOf(context))}';
      final styledOptionTitle = Xhtml.toWidget(context, widget.location.top,
          optionTitle, choice.valueStringElement?.extension_,
          width: 100, height: 100);

      choices.add(isMultipleChoice
          ? CheckboxListTile(
              title: styledOptionTitle,
              value: value?.coding?.firstWhereOrNull(
                      (coding) => coding.code?.value == choice.optionCode) !=
                  null,
              onChanged: (bool? newValue) {
                value = _fillToggledValue(choice.optionCode);
              })
          : RadioListTile<String>(
              title: styledOptionTitle,
              value: choice.optionCode,
              groupValue: _choiceString(value),
              onChanged: (String? newValue) {
                value = _fillValue(newValue);
              }));
    }

    if (qi.extension_
                ?.extensionOrNull(
                    'http://hl7.org/fhir/StructureDefinition/questionnaire-choiceOrientation')
                ?.valueCode
                ?.value ==
            'horizontal' &&
        MediaQuery.of(context).size.width > 750) {
      return Card(
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          child: Table(children: [TableRow(children: choices)]));
    } else {
      return Card(
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: choices,
          ));
    }
  }

  Widget _buildLookupAnswers(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return FDashAutocomplete<QuestionnaireAnswerOption>(
      initialValue: value?.localizedDisplay(locale),
      displayStringForOption: (answerOption) =>
          answerOption.localizedDisplay(locale),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<QuestionnaireAnswerOption>.empty();
        }
        return _answerOptions.values.where((QuestionnaireAnswerOption option) {
          return option
              .localizedDisplay(locale)
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (QuestionnaireAnswerOption selectedOption) {
        value = _fillValue(selectedOption.optionCode);
      },
    );
  }
}
