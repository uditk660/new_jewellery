class StockMovementsController < ApplicationController
  def create
    @inventory_item = InventoryItem.find(params[:inventory_item_id])
    grams = params[:change_grams].to_i
    type = params[:movement_type].presence || 'adjustment'
    note = params[:note]

    if grams.zero?
      redirect_to inventory_item_path(@inventory_item), alert: 'Enter a weight change in grams.'
      return
    end

    @inventory_item.adjust!(grams, movement_type: type, note: note)
    redirect_to inventory_item_path(@inventory_item), notice: 'Stock book updated.'
  rescue ActiveRecord::RecordInvalid
    redirect_to inventory_item_path(@inventory_item), alert: @inventory_item.errors.full_messages.to_sentence.presence || 'Could not apply this movement.'
  rescue ActiveRecord::RecordNotFound
    redirect_to inventory_items_path, alert: 'That stock card was not found.'
  end
end
