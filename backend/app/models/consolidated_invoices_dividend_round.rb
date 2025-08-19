# frozen_string_literal: true

class ConsolidatedInvoicesDividendRound < ApplicationRecord
  belongs_to :consolidated_invoice
  belongs_to :dividend_round
end
