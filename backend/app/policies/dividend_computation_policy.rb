# frozen_string_literal: true

class DividendComputationPolicy < ApplicationPolicy
  def index?
    return false unless company.equity_enabled?

    company_administrator.present? || company_lawyer.present?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def approve?
    index?
  end
end
