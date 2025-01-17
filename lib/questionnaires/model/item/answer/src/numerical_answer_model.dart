import 'package:faiadashu/coding/coding.dart';
import 'package:faiadashu/fhir_types/fhir_types.dart';
import 'package:faiadashu/l10n/l10n.dart';
import 'package:faiadashu/logging/logging.dart';
import 'package:faiadashu/questionnaires/model/model.dart';
import 'package:fhir/r4.dart';
import 'package:intl/intl.dart';

/// Models numerical answers.
class NumericalAnswerModel extends AnswerModel<String, Quantity> {
  static final _logger = Logger(NumericalAnswerModel);

  late final String _numberPattern;
  late final bool _isSliding;
  late final double _minValue;
  late final double _maxValue;
  late final int _maxDecimal;
  late final NumberFormat _numberFormat;
  late final double? _sliderStepValue;
  late final int? _sliderDivisions;

  RenderingString? _upperSliderLabel;
  RenderingString? _lowerSliderLabel;

  RenderingString? get upperSliderLabel => _upperSliderLabel;
  RenderingString? get lowerSliderLabel => _lowerSliderLabel;

  int? get sliderDivisions => _sliderDivisions;
  double? get sliderStepValue => _sliderStepValue;

  String get numberPattern => _numberPattern;
  bool get isSliding => _isSliding;
  double get minValue => _minValue;
  double get maxValue => _maxValue;
  int get maxDecimal => _maxDecimal;
  NumberFormat get numberFormat => _numberFormat;

  late final Map<String, Coding> _units;

  bool get hasUnit => value?.hasUnit ?? false;

  bool get hasUnitChoices => _units.isNotEmpty;

  bool get hasSingleUnitChoice => _units.length == 1;

  Iterable<Coding> get unitChoices => _units.values;

  Coding? unitChoiceByKey(String? key) {
    return (key != null) ? _units[key] : null;
  }

  String keyForUnitChoice(Coding coding) {
    final choiceString =
        (coding.code != null) ? coding.code?.value : coding.display;

    if (choiceString == null) {
      throw QuestionnaireFormatException(
        'Insufficient info for key string in $coding',
        coding,
      );
    } else {
      return choiceString;
    }
  }

  /// Returns a unique slug for the current unit.
  String? get keyOfUnit {
    if (!(value?.hasUnit ?? false)) {
      return null;
    }

    final coding =
        Coding(system: value?.system, code: value?.code, display: value?.unit);

    return keyForUnitChoice(coding);
  }

  NumericalAnswerModel(QuestionItemModel responseModel) : super(responseModel) {
    _isSliding =
        questionnaireItemModel.questionnaireItem.isItemControl('slider');

    final minValueExtension = qi.extension_
        ?.extensionOrNull('http://hl7.org/fhir/StructureDefinition/minValue');
    final maxValueExtension = questionnaireItemModel
        .questionnaireItem.extension_
        ?.extensionOrNull('http://hl7.org/fhir/StructureDefinition/maxValue');
    _minValue = minValueExtension?.valueDecimal?.value ??
        minValueExtension?.valueInteger?.value?.toDouble() ??
        0.0;
    _maxValue = maxValueExtension?.valueDecimal?.value ??
        maxValueExtension?.valueInteger?.value?.toDouble() ??
        (_isSliding ? modelDefaults.sliderMaxValue : double.maxFinite);

    if (_isSliding) {
      final sliderStepValueExtension = qi.extension_?.extensionOrNull(
        'http://hl7.org/fhir/StructureDefinition/questionnaire-sliderStepValue',
      );
      _sliderStepValue = sliderStepValueExtension?.valueDecimal?.value ??
          sliderStepValueExtension?.valueInteger?.value?.toDouble();
      _sliderDivisions = (_sliderStepValue != null)
          ? ((_maxValue - _minValue) / _sliderStepValue!).round()
          : null;

      _upperSliderLabel = questionnaireItemModel.upperTextItem?.text;
      _lowerSliderLabel = questionnaireItemModel.lowerTextItem?.text;
    }

    // TODO: Evaluate max length
    switch (qi.type) {
      case QuestionnaireItemType.integer:
        _maxDecimal = 0;
        break;
      case QuestionnaireItemType.decimal:
      case QuestionnaireItemType.quantity:
        // TODO: Evaluate special extensions for quantities
        _maxDecimal = qi.extension_
                ?.extensionOrNull(
                  'http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces',
                )
                ?.valueInteger
                ?.value ??
            modelDefaults.maxDecimal;
        break;
      default:
        throw StateError('item.type cannot be ${qi.type}');
    }

    // Build a number format based on item and SDC properties.
    final maxIntegerDigits = (_maxValue != double.maxFinite)
        ? '############'.substring(0, _maxValue.toInt().toString().length)
        : '############';
    final maxFractionDigits =
        (_maxDecimal != 0) ? '.0#####'.substring(0, _maxDecimal + 1) : '';

    _numberPattern = '$maxIntegerDigits$maxFractionDigits';

    _logger.debug(
      'input format for ${questionnaireItemModel.linkId}: "$_numberPattern"',
    );

    _numberFormat = NumberFormat(
      _numberPattern,
      locale.toLanguageTag(),
    ); // TODO: toString or toLanguageTag?

    _units = <String, Coding>{};
    final unitsUri = qi.extension_
        ?.extensionOrNull(
          'http://hl7.org/fhir/StructureDefinition/questionnaire-unitValueSet',
        )
        ?.valueCanonical
        .toString();
    if (unitsUri != null) {
      questionnaireItemModel.questionnaireModel.forEachInValueSet(
        unitsUri,
        (coding) {
          _units[keyForUnitChoice(coding)] = coding;
        },
        context: qi.linkId,
      );
    }
  }

  @override
  RenderingString get display => (value != null)
      ? RenderingString.fromText(
          value!.format(locale, defaultText: AnswerModel.nullText),
        )
      : RenderingString.nullText;

  @override
  String? validateInput(String? inputValue) {
    if (inputValue == null || inputValue.isEmpty) {
      return null;
    }
    num number = double.nan;
    try {
      number = numberFormat.parse(inputValue);
    } catch (_) {
      // Ignore FormatException, number remains nan.
    }
    if (number == double.nan) {
      return lookupFDashLocalizations(locale).validatorNan;
    }
    if (number > _maxValue) {
      return lookupFDashLocalizations(locale)
          .validatorMaxValue(Decimal(_maxValue).format(locale));
    }
    if (number < _minValue) {
      return lookupFDashLocalizations(locale)
          .validatorMinValue(Decimal(_minValue).format(locale));
    }
  }

  /// Returns a modified copy of the current [value].
  ///
  /// * Keeps the numerical value
  /// * Updates the unit based on a key as returned by [keyForUnitChoice]
  Quantity? copyWithUnit(String? unitChoiceKey) {
    final unitCoding = unitChoiceByKey(unitChoiceKey);

    return (value != null)
        ? value!.copyWith(
            unit: unitCoding?.localizedDisplay(locale),
            system: unitCoding?.system,
            code: unitCoding?.code,
          )
        : Quantity(
            unit: unitCoding?.localizedDisplay(locale),
            system: unitCoding?.system,
            code: unitCoding?.code,
          );
  }

  /// Returns a modified copy of the current [value].
  ///
  /// * Updates the numerical value based on a [Decimal]
  /// * Keeps the unit
  Quantity? copyWithValue(Decimal? newValue) {
    return (value != null)
        ? value!.copyWith(value: newValue)
        : Quantity(value: newValue);
  }

  /// Returns a modified copy of the current [value].
  ///
  /// * Updates the numerical value based on text input
  /// * Keeps the unit
  Quantity? copyWithTextInput(String textInput) {
    final valid = validateInput(textInput) == null;
    final dataAbsentReasonExtension = !valid
        ? [
            FhirExtension(
              url: dataAbsentReasonExtensionUrl,
              valueCode: dataAbsentReasonAsTextCode,
            ),
          ]
        : null;

    return textInput.trim().isEmpty
        ? value?.copyWith(value: null)
        : value == null
            ? Quantity(
                value: Decimal(numberFormat.parse(textInput)),
                extension_: dataAbsentReasonExtension,
              )
            : value!.copyWith(
                value: Decimal(numberFormat.parse(textInput)),
                extension_: dataAbsentReasonExtension,
              );
  }

  @override
  QuestionnaireResponseAnswer? createFhirAnswer(
    List<QuestionnaireResponseItem>? items,
  ) {
    _logger.debug('createFhirAnswer: $value');
    if (value == null) {
      return null;
    }

    switch (qi.type) {
      case QuestionnaireItemType.decimal:
        return (value!.value != null)
            ? QuestionnaireResponseAnswer(
                valueDecimal: value!.value,
                extension_: value!.extension_,
                item: items,
              )
            : null;
      case QuestionnaireItemType.quantity:
        return QuestionnaireResponseAnswer(
          valueQuantity: value,
          extension_: value!.extension_,
          item: items,
        );
      case QuestionnaireItemType.integer:
        return (value!.value != null)
            ? QuestionnaireResponseAnswer(
                valueInteger: Integer(value!.value!.value!.round()),
                extension_: value!.extension_,
                item: items,
              )
            : null;
      default:
        throw StateError('item.type cannot be ${qi.type}');
    }
  }

  @override
  String? get isComplete {
    // TODO: Check the actual value
    return null;
  }

  @override
  bool get isUnanswered => (value == null) || (value!.value == null);

  @override
  void populateFromExpression(dynamic evaluationResult) {
    if (evaluationResult == null) {
      value = null;

      return;
    }

    final unitCoding = qi.computableUnit;

    // OPTIMIZE: Submit improvement to Grey: Decimal factory should accept Decimal inValue
    final quantityValue = (evaluationResult is Decimal)
        ? evaluationResult
        : Decimal(evaluationResult);

    value = Quantity(
      value: quantityValue,
      unit: unitCoding?.localizedDisplay(locale),
      system: unitCoding?.system,
      code: unitCoding?.code,
      extension_: (unitCoding != null &&
              (qi.type == QuestionnaireItemType.decimal ||
                  qi.type == QuestionnaireItemType.integer))
          ? [
              FhirExtension(
                url: FhirUri(
                  'http://hl7.org/fhir/StructureDefinition/questionnaire-unit',
                ),
                valueCoding: unitCoding,
              ),
            ]
          : null,
    );
  }

  @override
  void populate(QuestionnaireResponseAnswer answer) {
    value = answer.valueQuantity ??
        ((answer.valueDecimal != null && answer.valueDecimal!.isValid)
            ? Quantity(value: answer.valueDecimal)
            : (answer.valueInteger != null && answer.valueInteger!.isValid)
                ? Quantity(
                    value: Decimal(answer.valueInteger!.value!.toDouble()),
                  )
                : null);
  }
}
