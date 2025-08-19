class CreateConsolidatedInvoicesDividendRounds < ActiveRecord::Migration[7.2]
  def change
    create_table :consolidated_invoices_dividend_rounds do |t|
      t.references :consolidated_invoice, null: false, foreign_key: true
      t.references :dividend_round, null: false, foreign_key: true
      t.timestamps
    end

    add_index :consolidated_invoices_dividend_rounds,
              [:consolidated_invoice_id, :dividend_round_id],
              unique: true,
              name: 'index_consolidated_invoices_dividend_rounds_unique'
  end
end
