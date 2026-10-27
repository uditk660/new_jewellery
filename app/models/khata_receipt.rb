class KhataReceipt < ActiveRecord::Base
  METHODS = %w[Cash Card Online PhonePe Paytm GPay Gold Silver Others].freeze

  belongs_to :customer
  has_many :payments, dependent: :nullify
  has_one :ledger_entry, dependent: :nullify

  PREFIX = { 'credit' => 'KR', 'opening' => 'KO', 'debit' => 'KD' }.freeze

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :received_on, presence: true
  validates :kind, inclusion: { in: PREFIX.keys }

  class Refused < StandardError; end

  # Opening or charge on the khata: the client owes more, and gets a slip for it.
  def self.post_entry!(customer:, kind:, amount_cents:, received_on:, note: nil)
    kind = kind.to_s
    raise Refused, 'Choose opening or charge.' unless %w[opening debit].include?(kind)
    raise Refused, 'Amount must be greater than ₹0.' unless amount_cents.to_i.positive?

    transaction do
      customer.lock!
      customer.orders.reset
      customer.ledger_entries.reset
      before = customer.live_outstanding_cents
      receipt = create!(customer: customer, kind: kind, amount_cents: amount_cents.to_i,
                        received_on: received_on || Time.zone.today, note: note.to_s.strip.presence&.first(160),
                        balance_before_cents: before)
      receipt.assign_number!
      LedgerEntry.create!(customer: customer, kind: kind, amount_cents: amount_cents.to_i, entry_date: receipt.received_on,
                          note: receipt.note, khata_receipt_id: receipt.id)
      receipt.snapshot!(customer)
      receipt
    end
  end

  # Slip for an entry posted before slips existed, using the balances from the statement.
  def self.for_entry!(entry, balance_after_cents:)
    entry.with_lock do
      next entry.khata_receipt if entry.khata_receipt

      signed = entry.credit? ? -entry.amount_cents.to_i : entry.amount_cents.to_i
      receipt = create!(customer: entry.customer, kind: entry.kind, amount_cents: entry.amount_cents,
                        received_on: entry.entry_date, note: entry.note,
                        payment_method: entry.credit? ? 'Not noted' : nil,
                        balance_before_cents: balance_after_cents - signed,
                        balance_after_cents: balance_after_cents,
                        deposited_to_date_cents: entry.customer.deposited_to_date_cents(upto: entry.created_at),
                        created_at: entry.created_at)
      receipt.assign_number!
      entry.update_columns(khata_receipt_id: receipt.id)
      receipt
    end
  end

  def assign_number!
    update_columns(receipt_number: "#{PREFIX[kind]}-#{received_on.strftime('%Y%m%d')}-#{id.to_s.rjust(4, '0')}")
  end

  def snapshot!(customer)
    customer.orders.reset
    customer.ledger_entries.reset
    customer.recompute_balance!
    update_columns(balance_after_cents: customer.live_outstanding_cents,
                   deposited_to_date_cents: customer.deposited_to_date_cents)
  end

  def credit?
    kind.to_s == 'credit'
  end

  def title
    case kind.to_s
    when 'opening' then 'Opening balance'
    when 'debit' then 'Debit note'
    else 'Receipt'
    end
  end

  # Takes a deposit on the khata. Pending bills are paid first, oldest first, as
  # real bill payments; whatever is left clears opening and charge lines. The
  # deposit can never exceed what the client owes, so the khata cannot go below zero.
  def self.post!(customer:, amount_cents:, payment_method:, received_on:, note: nil)
    amount = amount_cents.to_i
    method = payment_method.to_s.strip
    raise Refused, 'Choose how the client paid.' unless METHODS.include?(method)
    raise Refused, 'Deposit must be greater than ₹0.' unless amount.positive?

    transaction do
      customer.lock!
      customer.orders.reset
      customer.ledger_entries.reset
      before = customer.live_outstanding_cents
      raise Refused, 'This khata is already settled. There is nothing to receive.' unless before.positive?
      if amount > before
        raise Refused, "Deposit cannot exceed the outstanding of #{format('₹%.2f', Paise.rupees(before))}."
      end
      if amount % 100 != 0 && amount != before
        raise Refused, 'Receive in whole rupees, or the exact outstanding to settle the khata.'
      end

      receipt = create!(customer: customer, kind: 'credit', amount_cents: amount, payment_method: method,
                        received_on: received_on || Time.zone.today, note: note.to_s.strip.presence&.first(160),
                        balance_before_cents: before)
      receipt.assign_number!

      left = amount
      pending = customer.orders.select { |order| order.status.to_s == 'pending' }
                        .sort_by { |order| [order.try(:sale_date) || order.created_at.to_date, order.id] }
      pending.each do |order|
        whole_left = (left / 100) * 100
        apply = [whole_left, order.remaining_cents].min
        next unless apply.positive?

        payment = Payment.create!(order_id: order.id, customer_id: customer.id, amount_cents: apply,
                                  payment_method: method, khata_receipt_id: receipt.id,
                                  note: "Khata receipt #{receipt.receipt_number}")
        payment.update_columns(receipt_number: "RCT-#{Time.zone.today.strftime('%Y%m%d')}-#{payment.id.to_s.rjust(4, '0')}")
        order.payments.reset
        order.update!(status: 'paid') if order.remaining_cents.zero?
        left -= apply
        break if left.zero?
      end

      if left.positive?
        LedgerEntry.create!(customer: customer, kind: 'credit', amount_cents: left, entry_date: receipt.received_on,
                            note: "Khata receipt #{receipt.receipt_number}", khata_receipt_id: receipt.id)
      end

      customer.orders.reset
      customer.ledger_entries.reset
      raise Refused, 'Deposit would take the khata below zero.' if customer.live_outstanding_cents.negative?

      receipt.snapshot!(customer)
      receipt
    end
  end

  def amount
    Paise.rupees(amount_cents)
  end

  def settled?
    balance_after_cents.to_i <= 0
  end

  # Where this deposit landed: each bill it paid, then any amount on account.
  def allocations
    return [] unless credit?

    lines = payments.includes(:order).map do |payment|
      order = payment.order
      { label: order&.invoice_number.presence || (order ? format('INV-%03d', order.id) : 'Bill'), cents: payment.amount_cents.to_i }
    end
    lines << { label: 'Opening & charges on the khata', cents: ledger_entry.amount_cents.to_i } if ledger_entry
    lines
  end
end
