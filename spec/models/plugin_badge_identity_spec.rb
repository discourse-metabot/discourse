# frozen_string_literal: true

RSpec.describe Badge, ".seed_plugin" do
  def seed(key: "synthetic:badge", name: "Synthetic Badge", **options)
    Badge.seed_plugin(
      key,
      name: name,
      legacy_queries: ["SELECT user_id, current_timestamp granted_at FROM voice_sessions"],
      **options,
    ) do |badge|
      badge.badge_type_id = BadgeType::Bronze
      badge.query = "SELECT user_id, current_timestamp granted_at FROM live_sessions"
      badge.trigger = Badge::Trigger::None
      badge.auto_revoke = false
      badge.multiple_grant = false
      badge.target_posts = false
      badge.show_posts = false
      badge.default_enabled = true
    end
  end

  it "persists a stable ID and ownership across repeated seeds" do
    badge = seed
    expect(seed.id).to eq(badge.id)
    expect(Badge.where(plugin_badge_key: "synthetic:badge").count).to eq(1)
  end

  it "does not take over a same-name custom badge" do
    custom = Fabricate(:badge, name: "Synthetic Badge", system: false)
    original = custom.reload.attributes
    expect(seed).to be_nil
    expect(custom.reload.attributes).to eq(original)
  end

  it "does not take over an unrelated same-name system badge" do
    custom = Fabricate(:badge, name: "Synthetic Badge", system: true, query: "SELECT 123")
    original = custom.reload.attributes
    expect(seed).to be_nil
    expect(custom.reload.attributes).to eq(original)
  end

  it "adopts a historical definition without moving IDs, grants or titles" do
    historical = seed
    historical.update_columns(plugin_badge_key: nil, enabled: false)
    historical.update_columns(query: historical.query.gsub("live_sessions", "voice_sessions"))
    award = Fabricate(:user_badge, badge: historical)
    profile = award.user.user_profile
    profile.update!(granted_title_badge_id: historical.id)

    expect(seed.id).to eq(historical.id)
    expect(award.reload.badge_id).to eq(historical.id)
    expect(profile.reload.granted_title_badge_id).to eq(historical.id)
    expect(historical.reload.enabled).to eq(false)
  end

  it "finds owned badges by ID after a rename, even if a custom badge takes the old name" do
    original = seed
    original.update!(name: "Site-renamed badge")
    custom = Fabricate(:badge, name: "Synthetic Badge", system: false)
    custom_attributes = custom.reload.attributes

    expect(seed.id).to eq(original.id)
    expect(original.reload.name).to eq("Site-renamed badge")
    expect(custom.reload.attributes).to eq(custom_attributes)
  end

  it "does not adopt a legacy definition without a query using only its name and system flag" do
    legacy =
      Fabricate(:badge, name: "Instant Badge", system: true, badge_type_id: BadgeType::Bronze)
    expect(
      Badge.seed_plugin("synthetic:instant", name: "Instant Badge") do |badge|
        badge.badge_type_id = BadgeType::Bronze
      end,
    ).to be_nil
    expect(legacy.reload.plugin_badge_key).to be_nil
  end

  it "can explicitly refuse adoption of a definition with an ambiguous history" do
    historical = seed
    historical.update_columns(plugin_badge_key: nil)
    expect(seed(adopt_legacy: false)).to be_nil
    expect(historical.reload.plugin_badge_key).to be_nil
  end

  it "does not allow reassignment of established ownership" do
    badge = seed
    expect(badge.update(plugin_badge_key: "another:badge")).to eq(false)
    expect(badge.reload.plugin_badge_key).to eq("synthetic:badge")
  end

  it "does not collapse whitespace or substitute table names inside SQL literals" do
    historical = seed
    historical.update_columns(plugin_badge_key: nil, query: "SELECT 'a  b', 'voice_sessions'")
    result =
      Badge.seed_plugin("synthetic:badge", name: "Synthetic Badge") do |badge|
        badge.badge_type_id = BadgeType::Bronze
        badge.query = "SELECT 'a b', 'live_sessions'"
        badge.trigger = Badge::Trigger::None
        badge.auto_revoke = false
        badge.multiple_grant = false
        badge.target_posts = false
        badge.show_posts = false
      end
    expect(result).to be_nil
    expect(historical.reload.plugin_badge_key).to be_nil
  end

  it "does not adopt a different protected listable value" do
    historical = seed
    historical.update_columns(plugin_badge_key: nil, listable: false)
    expect(seed).to be_nil
    expect(historical.reload.plugin_badge_key).to be_nil
  end

  it "validates namespaced keys" do
    expect { seed(key: "Synthetic Badge") }.to raise_error(ArgumentError)
  end

  it "enforces ownership uniqueness in the database" do
    badge = seed
    other = Fabricate(:badge)
    expect do
      Badge.transaction(requires_new: true) do
        other.update_columns(plugin_badge_key: badge.plugin_badge_key)
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
