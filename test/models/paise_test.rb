require 'minitest/autorun'
require_relative '../../app/models/paise'

class PaiseTest < Minitest::Test
  def test_strict_parse_rejects_non_numbers
    assert_nil Paise.dec('abc')
    assert_nil Paise.dec('1e400')
    assert_nil Paise.dec('Infinity')
    assert_nil Paise.dec('12abc')
    assert_nil Paise.dec('')
    assert_nil Paise.dec(Float::INFINITY)
    assert_equal BigDecimal('1250.5'), Paise.dec('1,250.50')
    assert_equal BigDecimal('-3'), Paise.dec('-3')
  end

  def test_half_up_where_floats_drift
    # 1.005 * 100 is 100.49999... as a Float
    assert_equal 101, Paise.from_rupees('1.005')
    assert_equal 268, Paise.from_rupees('2.675')
    assert_equal BigDecimal('2.68'), Paise.round2('2.675')
    assert_equal 0, Paise.from_rupees(nil)
  end

  def test_percent_of_rounds_each_half_to_the_paisa
    # 1.5% of ₹1,000.33 = 15.00495 → ₹15.00
    assert_equal 1500, Paise.percent_of(100_033, '1.5')
    # 1.5% of ₹1,000.30 = 15.0045 → ₹15.00 ; 1.5% of ₹1,000.70 = 15.0105 → ₹15.01
    assert_equal 1500, Paise.percent_of(100_030, '1.5')
    assert_equal 1501, Paise.percent_of(100_070, '1.5')
    # exact half paisa rounds up
    assert_equal 2, Paise.percent_of(100, '1.5')
  end

  def test_round_rupee_half_up
    assert_equal 349_200, Paise.round_rupee(349_170)
    assert_equal 349_200, Paise.round_rupee(349_150)
    assert_equal 349_100, Paise.round_rupee(349_149)
    assert_equal 0, Paise.round_rupee(0)
  end

  def test_large_amounts_stay_exact
    assert_equal 99_999_999_999, Paise.from_rupees('999999999.99')
    assert_equal BigDecimal('999999999.99'), Paise.round2('999999999.99')
  end
end
