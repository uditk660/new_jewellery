module MaisonHelper
  PHOTOS = {
    hero: '1515562141207-7a88fb7ce338',
    ring: '1605100804763-247f67b3557e',
    necklace: '1599643478518-a784e5dc4c8f',
    earrings: '1535632066927-ab7c9ab60908',
    gold: '1617038260897-41a1f14a8ca0',
    bracelet: '1611591437281-460bfbe1220a',
    bench: '1617038220319-276d3cfab638',
    portrait: '1602173574767-37ac01994b2a',
    sparkle: '1515562141207-7a88fb7ce338',
    tray: '1630019852942-f89202989a59'
  }.freeze

  def maison_photo(key, width: 1600)
    id = PHOTOS.fetch(key)
    "https://images.unsplash.com/photo-#{id}?auto=format&fit=crop&w=#{width}&q=80"
  end

  def maison_nav_link(label, path)
    on = current_page?(path)
    link_to label, path, class: (on ? 'is-on' : nil)
  end
end
