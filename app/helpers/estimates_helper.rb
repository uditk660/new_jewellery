module EstimatesHelper
  # ₹1,50,000.00 style, with a true minus sign; "Nil" for zero when asked.
  def estimate_rupees(cents, nil_zero: false, sign: false)
    cents = cents.to_i
    return 'Nil' if nil_zero && cents.zero?

    whole, paise = cents.abs.divmod(100)
    digits = whole.to_s
    grouped = digits.length > 3 ? "#{digits[0..-4].reverse.scan(/\d{1,2}/).join(',').reverse},#{digits[-3..]}" : digits
    prefix = cents.negative? ? '−' : (sign && cents.positive? ? '+' : '')
    "#{prefix}₹#{grouped}.#{paise.to_s.rjust(2, '0')}"
  end

  def estimate_grams(mg, nil_zero: false, blank_zero: false)
    mg = mg.to_i
    return 'Nil' if nil_zero && mg.zero?
    return '' if blank_zero && mg.zero?

    text = format('%.3f', mg.abs / 1000.0)
    mg.negative? ? "−#{text}" : text
  end
end
