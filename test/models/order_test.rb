ENV['RAILS_ENV'] ||= 'development'
require_relative '../../config/environment'
require 'minitest/autorun'

# Builds bills in memory only; nothing is saved.
class OrderTest < Minitest::Test
  def bill(discount: 0, charges: 0, cgst: 1.5, sgst: 1.5)
    Order.new(status: 'pending', discount: discount, charges: charges, cgst_rate: cgst, sgst_rate: sgst)
  end

  def add_line(order, rate:, net:, qty: 1, making: 0, additional: 0)
    metal = (BigDecimal(rate.to_s) * BigDecimal(net.to_s) * qty).round(2, BigDecimal::ROUND_HALF_UP)
    order.line_items.build(
      price_cents: Paise.from_rupees(BigDecimal(rate.to_s) * BigDecimal(net.to_s)),
      quantity: qty, weight: net, net_weight: net, gross_weight: net,
      rate: metal, making_charge: making, additional_charge: additional
    )
  end

  def test_line_uses_stored_metal_amount_and_quantity
    order = bill
    add_line(order, rate: 6250.75, net: 3.33, qty: 2, making: 1500, additional: 120.5)
    li = order.line_items.first
    # 6250.75 × 3.33 × 2 = 41630.00 (exact 41629.995 → half-up)
    assert_equal 4_163_000, li.metal_cents
    assert_equal 150_000, li.making_cents
    assert_equal 24_100, li.additional_cents
    assert_equal 4_337_100, li.line_amount_cents
  end

  def test_discount_and_charges_apply_after_tax
    order = bill(discount: 100.10, charges: 50.05)
    add_line(order, rate: 7000, net: 1.43, making: 0)
    b = order.bill_breakdown
    # tax on the full ₹10,010.00: 1.5% = ₹150.15 each → ₹10,310.30 after tax
    assert b[:discount_after_tax]
    assert_equal 1_001_000, b[:taxable_cents]
    assert_equal 15_015, b[:cgst_cents]
    assert_equal 15_015, b[:sgst_cents]
    assert_equal 1_031_030, b[:after_tax_cents]
    # − ₹100.10 + ₹50.05 = ₹10,260.25 → collected ₹10,260
    assert_equal 1_026_025, order.total_cents
    assert_equal 1_026_000, order.payable_cents
  end

  def test_settled_bills_keep_discount_before_tax
    order = bill(discount: 100.10, charges: 50.05)
    order.discount_after_tax = false
    add_line(order, rate: 7000, net: 1.43, making: 0)
    b = order.bill_breakdown
    # subtotal 10010.00 − 100.10 + 50.05 = 9959.95; 1.5% = 149.39925 → 149.40
    assert_equal 1_001_000, b[:subtotal_cents]
    assert_equal 995_995, b[:taxable_cents]
    assert_equal 14_940, b[:cgst_cents]
    assert_equal 14_940, b[:sgst_cents]
    assert_equal b[:taxable_cents] + b[:cgst_cents] + b[:sgst_cents], b[:total_cents]
    assert_equal 1_025_875, order.total_cents
  end

  def test_rates_are_independent
    order = bill(cgst: 1.5, sgst: 2.5)
    add_line(order, rate: 1000, net: 10)
    assert_equal 15_000, order.cgst_amount_cents
    assert_equal 25_000, order.sgst_amount_cents
    assert_equal 1_040_000, order.total_cents
  end

  def test_weights_multiply_by_quantity
    order = bill
    add_line(order, rate: 100, net: 2.5, qty: 3)
    assert_equal BigDecimal('7.5'), BigDecimal(order.total_net_grams.to_s)
  end

  def pay!(order, rupees)
    order.payments.build(amount_cents: rupees * 100)
    order.association(:payments).loaded!
  end

  # ₹3,390 subtotal + 1.5% + 1.5% = ₹3,491.70, collected as ₹3,492.
  def bill_3491_70
    order = bill
    add_line(order, rate: 1000, net: 3, making: 390)
    order
  end

  def test_due_is_rounded_off_to_the_rupee
    order = bill_3491_70
    assert_equal 349_170, order.total_cents
    assert_equal 349_200, order.payable_cents
    assert_equal 30, order.round_off_cents
    assert_equal 349_200, order.remaining_cents
  end

  def test_part_payments_count_down_in_whole_rupees
    order = bill_3491_70
    pay!(order, 500)
    assert_equal 299_200, order.remaining_cents
    pay!(order, 1000)
    assert_equal 199_200, order.remaining_cents
    pay!(order, 1992)
    assert_equal 0, order.remaining_cents
  end

  def test_rounds_down_below_fifty_paise
    order = bill(cgst: 0, sgst: 0)
    add_line(order, rate: 100, net: 34.91, making: 0.49)
    assert_equal 349_149, order.total_cents
    assert_equal 349_100, order.remaining_cents
    pay!(order, 3491)
    assert_equal 0, order.remaining_cents
  end

  def test_remaining_never_negative_with_no_payments
    order = bill
    add_line(order, rate: 100, net: 1)
    assert_equal 0, order.paid_cents
    assert_equal order.total_cents, order.remaining_cents
  end
end
