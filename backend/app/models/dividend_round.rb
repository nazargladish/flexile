# frozen_string_literal: true

class DividendRound < ApplicationRecord
  include ExternalId

  belongs_to :company
  has_many :dividends
  has_many :investor_dividend_rounds
  has_one :dividend_computation
  has_many :consolidated_invoices_dividend_rounds, dependent: :destroy
  has_many :consolidated_invoices, through: :consolidated_invoices_dividend_rounds

  validates :issued_at, presence: true
  validates :number_of_shares, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :number_of_shareholders, presence: true, numericality: { greater_than: 0 }
  validates :total_amount_in_cents, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w(Issued Paid) }
  validates :ready_for_payment, inclusion: { in: [true, false] }

  scope :ready_for_payment, -> { where(ready_for_payment: true) }

  # TODO(naz): Probabaly, dividend round can not have multiple consolidated invoices
  def consolidated_invoice
    consolidated_invoices.first
  end

  def fund_pull_triggered?
    consolidated_invoice.present?
  end

  # TODO(naz): Hm, how it's gonna work
  def fund_pull_status
    return "not_triggered" unless consolidated_invoice

    if consolidated_invoice.consolidated_payments.any?
      consolidated_invoice.consolidated_payments.last.status
    else
      "pending"
    end
  end

  def send_dividend_emails
    Rails.logger.info("Sending dividend issuance emails for dividend round #{id}")

    company.company_investors.joins(:dividends)
      .where(dividends: { dividend_round_id: id })
      .group(:id)
      .each do |investor|
        Rails.logger.info("Sending dividend issuance email to investor #{investor.id} for dividend round #{id}")

        investor_dividend_round = investor.investor_dividend_rounds.find_or_create_by!(dividend_round_id: id)
        investor_dividend_round.send_dividend_issued_email

        Rails.logger.info("Sent dividend issuance email to investor #{investor.id} for dividend round #{id}")
      end

    Rails.logger.info("Completed sending dividend issuance emails for dividend round #{id}")
  end
end
