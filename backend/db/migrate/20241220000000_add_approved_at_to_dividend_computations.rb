class AddApprovedAtToDividendComputations < ActiveRecord::Migration[7.0]
  def change
    add_column :dividend_computations, :approved_at, :datetime
    add_index :dividend_computations, :approved_at
  end
end