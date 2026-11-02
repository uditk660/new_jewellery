ENV['RAILS_ENV'] ||= 'development'
require_relative '../../config/environment'
require 'minitest/autorun'

# Each test runs inside a transaction that is rolled back.
class KhataReceiptTest < Minitest::Test
  def run(*args, &block)
    result = nil
    ActiveRecord::Base.transaction do
      result = super
      raise ActiveRecord::Rollback
    end
    result
  end

  def client_owing(opening_cents)
    customer = Customer.create!(first_name: 'Khata', last_name: 'Test', phone: "9#{rand(10**9).to_s.rjust(9, '0')}")
    LedgerEntry.create!(customer: customer, kind: 'opening', amount_cents: opening_cents, entry_date: Time.zone.today)
    customer.reload
  end

  def post(customer, cents, method: 'Cash')
    KhataReceipt.post!(customer: customer, amount_cents: cents, payment_method: method, received_on: Time.zone.today)
  end

  def test_refuses_more_than_outstanding
    customer = client_owing(100_000)
    error = assert_raises(KhataReceipt::Refused) { post(customer, 100_100) }
    assert_match(/cannot exceed/, error.message)
    assert_equal 100_000, customer.reload.live_outstanding_cents
  end

  def test_full_payment_settles_at_zero
    customer = client_owing(100_050)
    receipt = post(customer, 100_050)
    assert_equal 100_050, receipt.balance_before_cents
    assert_equal 0, receipt.balance_after_cents
    assert receipt.settled?
    assert_equal 0, customer.reload.live_outstanding_cents
    assert_raises(KhataReceipt::Refused) { post(customer, 100) }
  end

  def test_part_payment_must_be_whole_rupees
    customer = client_owing(100_050)
    assert_raises(KhataReceipt::Refused) { post(customer, 50_050) }
    receipt = post(customer, 50_000)
    assert_equal 50_050, receipt.balance_after_cents
  end

  def test_needs_a_payment_method
    customer = client_owing(10_000)
    assert_raises(KhataReceipt::Refused) { post(customer, 10_000, method: '') }
  end

  def test_opening_and_charge_get_their_own_slips
    customer = client_owing(10_000)
    opening = KhataReceipt.post_entry!(customer: customer, kind: 'opening', amount_cents: 5_000, received_on: Time.zone.today)
    charge = KhataReceipt.post_entry!(customer: customer, kind: 'debit', amount_cents: 2_550, received_on: Time.zone.today)
    assert_equal [10_000, 15_000], [opening.balance_before_cents, opening.balance_after_cents]
    assert_equal [15_000, 17_550], [charge.balance_before_cents, charge.balance_after_cents]
    assert_match(/\AKO-/, opening.receipt_number)
    assert_match(/\AKD-/, charge.receipt_number)
    assert_equal 'Debit note', charge.title
    assert_equal charge.id, charge.ledger_entry.khata_receipt_id
  end

  def test_slip_for_an_older_entry_is_made_once
    customer = client_owing(10_000)
    entry = customer.ledger_entries.first
    first = KhataReceipt.for_entry!(entry, balance_after_cents: 10_000)
    again = KhataReceipt.for_entry!(entry.reload, balance_after_cents: 10_000)
    assert_equal first.id, again.id
    assert_equal 0, first.balance_before_cents
  end

  def test_records_running_total_deposited
    customer = client_owing(30_000)
    post(customer, 10_000)
    second = post(customer, 20_000)
    assert_equal 30_000, second.deposited_to_date_cents
    assert_match(/\AKR-\d{8}-\d{4}\z/, second.receipt_number)
  end
end
