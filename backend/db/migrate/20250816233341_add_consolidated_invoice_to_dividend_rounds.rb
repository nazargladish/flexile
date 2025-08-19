class AddConsolidatedInvoiceToDividendRounds < ActiveRecord::Migration[8.0]
  def change
    add_reference :dividend_rounds, :consolidated_invoice, null: true, foreign_key: true
    add_index :dividend_rounds, :consolidated_invoice_id, unique: true
  end
end
