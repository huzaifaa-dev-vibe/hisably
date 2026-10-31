/// Domain-rule violations surfaced by repositories. The UI maps [code] to a
/// human-readable message; nothing here should ever crash the app.
enum DomainRule {
  amountMustBePositive,
  currencyMismatch,
  sameAccount,
  differentCurrencyRequired,
  accountNotFound,
  categoryNotFound,
  categoryDirectionMismatch,
  feeOutOfRange,
  toAmountRequired,
}

class DomainRuleException implements Exception {
  DomainRuleException(this.code, [this.detail]);

  final DomainRule code;
  final String? detail;

  @override
  String toString() => 'DomainRuleException(${code.name}${detail == null ? '' : ': $detail'})';
}
