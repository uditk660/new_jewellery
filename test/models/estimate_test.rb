ENV['RAILS_ENV'] ||= 'development'
require_relative '../../config/environment'
require 'minitest/autorun'

# Each test runs inside a transaction that is rolled back.
class EstimateTest < Minitest::Test
  def run(*args, &block)
    result = nil
    ActiveRecord::Base.transaction do
      result = super
      raise ActiveRecord::Rollback
    end
    result
  end

  def paper_slip
    estimate = Estimate.new(estimate_date: Date.new(2026, 9, 28), party_name: 'Sudhir Ji',
                            party_place: 'Jagdishpur, Ara', party_phone: '9835607332',
                            prev_ref: '4179-15/09/26', prev_amount_cents: 57_000)
    estimate.assign_rows(
      [
        { description: 'Jutiya', pcs: '4', net_weight: '5.950', tunch: '79.50', labour: '55', labour_on: 'pc' },
        { description: 'God locket', pcs: '1', net_weight: '1.980', tunch: '79.50', labour: '55', labour_on: 'pc' }
      ],
      [
        { kind: 'metal', description: 'Metal', weight: '4.100', touch: '99.50' },
        { kind: 'bhav', fine: '2.224', rate: '150000' },
        { kind: 'cash', amount: '34205' }
      ]
    )
    estimate
  end

  def test_matches_the_paper_rough_estimate
    estimate = paper_slip
    assert estimate.save, estimate.errors.full_messages.inspect
    assert_equal [4730, 1574], estimate.item_rows.map { |r| r['fine_mg'] }
    assert_equal [22_000, 5_500], estimate.item_rows.map { |r| r['amount_cents'] }
    assert_equal 7930, estimate.net_mg
    assert_equal 6304, estimate.fine_mg
    assert_equal 27_500, estimate.amount_cents
    assert_equal 84_500, estimate.net_total_amount_cents
    assert_equal [-4080, -2224, 0], estimate.settlement_rows.map { |r| r['fine_mg'] }
    assert_equal [0, 3_336_000, -3_420_500], estimate.settlement_rows.map { |r| r['amount_cents'] }
    assert estimate.settled?
  end

  def test_labour_per_gram_and_open_balance
    estimate = Estimate.new(estimate_date: Date.today, party_name: 'Walk-in')
    estimate.assign_rows([{ description: 'Chain', pcs: '1', net_weight: '10.000', tunch: '92', labour: '300', labour_on: 'g' }], [])
    assert estimate.save, estimate.errors.full_messages.inspect
    assert_equal 9200, estimate.closing_fine_mg
    assert_equal 300_000, estimate.closing_amount_cents
    refute estimate.settled?
  end

  def test_rejects_bad_numbers_and_empty_slips
    empty = Estimate.new(estimate_date: Date.today, party_name: 'X')
    empty.assign_rows([], [])
    refute empty.save
    assert_includes empty.errors.full_messages.join, 'at least one'

    bad = Estimate.new(estimate_date: Date.today, party_name: 'X')
    bad.assign_rows([{ description: 'Ring', pcs: '1.5', net_weight: 'abc', tunch: '120', labour: '0' }], [])
    refute bad.save
    text = bad.errors.full_messages.join(' ')
    assert_includes text, 'whole number'
    assert_includes text, 'net weight'
    assert_includes text, 'tunch'
  end

  def test_numbers_run_in_sequence_and_carry_forward
    customer = Customer.create!(first_name: 'Est', last_name: 'Test', phone: "9#{rand(10**9).to_s.rjust(9, '0')}")
    first = Estimate.new(estimate_date: Date.new(2026, 9, 15), party_name: 'Est Test', customer: customer)
    first.assign_rows([{ description: 'Ring', pcs: '1', net_weight: '2', tunch: '90', labour: '100' }], [])
    first.save!
    second = Estimate.new(estimate_date: Date.today, party_name: 'Other')
    second.assign_rows([], [{ kind: 'cash', amount: '10' }])
    second.save!
    assert_equal first.estimate_no + 1, second.estimate_no
    carry = Estimate.carry_forward_for(customer.id)
    assert_equal "#{first.estimate_no}-15/09/26", carry[:ref]
    assert_in_delta 1.8, carry[:fine]
    assert_in_delta 100.0, carry[:amount]
  end
end
