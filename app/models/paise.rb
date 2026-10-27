require 'bigdecimal'
require 'bigdecimal/util'

# Rupee arithmetic in whole paise. Every amount on a bill is an Integer number of
# paise, and every rounding is half-up to the paisa, so printed lines always add
# up to the printed total.
module Paise
  NUMERIC = /\A\s*-?\d+(\.\d+)?\s*\z/

  module_function

  # Strict parse of a form value or column into BigDecimal. Returns nil for blank
  # or non-numeric input (including "1e400", "Infinity", "12abc").
  def dec(value)
    case value
    when BigDecimal then value.finite? ? value : nil
    when Integer then BigDecimal(value)
    when Float then value.finite? ? BigDecimal(value.to_s) : nil
    when nil then nil
    else
      str = value.to_s.delete(',')
      str.match?(NUMERIC) ? BigDecimal(str.strip) : nil
    end
  end

  def dec!(value)
    dec(value) || BigDecimal('0')
  end

  # Round a rupee value to two decimals, half-up.
  def round2(value)
    dec!(value).round(2, BigDecimal::ROUND_HALF_UP)
  end

  def from_rupees(value)
    (dec!(value) * 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
  end

  def percent_of(paise, rate)
    (BigDecimal(paise.to_i) * dec!(rate) / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
  end

  # Nearest whole rupee in paise, half-up: 349170 → 349200, 349149 → 349100.
  def round_rupee(paise)
    (BigDecimal(paise.to_i) / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i * 100
  end

  def rupees(paise)
    paise.to_i / 100.0
  end
end
