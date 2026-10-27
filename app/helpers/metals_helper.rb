module MetalsHelper
  def purity_mark(purity)
    return '' if purity.blank?

    name = purity.name.to_s.strip
    fin = purity.fineness.to_s.strip.presence
    fin ? "#{name}/#{fin}" : name
  end

  # One chip per catalogue piece: CHAIN 18K/750 · 2.00 g
  def metal_hallmark_chip_labels(metal)
    pieces = metal.jewelry_items.reject { |j| j.archived? }
    pieces = pieces.sort_by { |j| [j.jewellery_category&.name.to_s, j.name.to_s, j.weight_grams.to_f] }
    if pieces.any?
      pieces.map { |item| metal_piece_chip_label(item) }
    else
      metal.purities.sort_by { |p| [p.position.to_i, p.name.to_s] }.map do |p|
        "#{p.name.to_s.upcase} #{purity_mark(p)} · #{p.available_weight_label}"
      end
    end
  end

  def metal_piece_chip_label(item)
    cat = item.jewellery_category&.name.to_s.strip.upcase.presence || 'PIECE'
    mark = purity_mark(item.purity)
    "#{cat} #{mark} · #{format('%.2f', item.weight_grams.to_f)} g"
  end

  # JHUMKA 18K/750 · NKM NATH 60 · …
  def metal_categories_line(metal)
    fallback = purity_mark(metal.purities.min_by { |p| p.position.to_i } || metal.purities.first)
    cats = metal.jewellery_categories.sort_by { |c| [c.position.to_i, c.name.to_s] }
    return '' if cats.empty?

    cats.map do |cat|
      piece = metal.jewelry_items.find do |j|
        !j.archived? && j.jewellery_category_id == cat.id && j.purity.present?
      end
      mark = piece ? purity_mark(piece.purity) : fallback
      label = cat.name.to_s.strip.upcase
      mark.present? ? "#{label} #{mark}" : label
    end.join(' · ')
  end
end
