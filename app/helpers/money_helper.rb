module MoneyHelper
  # Format an amount in rupees using the rupee symbol and two decimals.
  # Accepts numeric amounts already in rupees (not cents) or cents when :cents => true
  def format_rupees(amount, cents: false)
    return '' if amount.nil?
    value = cents ? (amount.to_f / 100.0) : amount.to_f
    # use Indian Rupee symbol
    "\u20B9#{'%.2f' % value}"
  end

  # Indian numbering: crore / lakh, for the invoice amount-in-words line.
  def rupees_in_words(amount)
    value = amount.to_f.round(2)
    rupees = value.to_i
    paise = ((value * 100).round - rupees * 100).abs
    words = "#{indian_integer_words(rupees)} rupees"
    words = "#{words} and #{indian_integer_words(paise)} paise" if paise.positive?
    "#{words} only".upcase
  end

  private

  INDIAN_ONES = %w[
    zero one two three four five six seven eight nine ten eleven twelve
    thirteen fourteen fifteen sixteen seventeen eighteen nineteen
  ].freeze
  INDIAN_TENS = %w[zero ten twenty thirty forty fifty sixty seventy eighty ninety].freeze

  def indian_integer_words(n)
    n = n.to_i
    return INDIAN_ONES[0] if n.zero?

    crore = n / 10_000_000
    n %= 10_000_000
    lakh = n / 100_000
    n %= 100_000
    thousand = n / 1_000
    rest = n % 1_000
    parts = []
    parts << "#{under_thousand_words(crore)} crore" if crore.positive?
    parts << "#{under_thousand_words(lakh)} lakh" if lakh.positive?
    parts << "#{under_thousand_words(thousand)} thousand" if thousand.positive?
    parts << under_thousand_words(rest) if rest.positive?
    parts.join(' ')
  end

  def under_thousand_words(n)
    n = n.to_i
    return '' if n.zero?
    return INDIAN_ONES[n] if n < 20
    return [INDIAN_TENS[n / 10], n % 10 > 0 ? INDIAN_ONES[n % 10] : nil].compact.join(' ') if n < 100

    [INDIAN_ONES[n / 100] + ' hundred', n % 100 > 0 ? under_thousand_words(n % 100) : nil].compact.join(' ')
  end
end
