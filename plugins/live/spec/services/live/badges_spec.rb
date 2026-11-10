# frozen_string_literal: true

RSpec.describe Live::Badges do
  before do
    SiteSetting.live_enabled = true
    SiteSetting.live_badges_enabled = true
  end

  def seed
    SeedFu.seed(Rails.root.join("plugins/live/db/fixtures"))
  end

  it "leaves custom Patron and its manually awarded grants untouched when Live is disabled" do
    Badge.where(name: "Patron").destroy_all
    patron =
      Fabricate(
        :badge,
        name: "Patron",
        system: false,
        badge_type_id: BadgeType::Gold,
        description: "Manual supporter badge",
      )
    award = Fabricate(:user_badge, badge: patron)
    original = patron.reload.attributes
    SiteSetting.live_enabled = false

    seed
    expect(patron.reload.attributes).to eq(original)
    expect(award.reload.badge_id).to eq(patron.id)
    expect(described_class.find("Live Patron").id).not_to eq(patron.id)
  end

  it "does not claim an already clobbered Patron as proven plugin ownership" do
    Badge.where(name: "Patron").destroy_all
    legacy =
      Fabricate(
        :badge,
        name: "Patron",
        system: true,
        query: "SELECT user_id, current_timestamp granted_at FROM voice_sessions",
        enabled: false,
      )
    award = Fabricate(:user_badge, badge: legacy)
    original = legacy.reload.attributes

    seed
    expect(legacy.reload.attributes).to eq(original)
    expect(award.reload.badge_id).to eq(legacy.id)
    expect(described_class.find("Live Patron").id).not_to eq(legacy.id)
  end

  it "does not let grouping changes control plugin ownership" do
    seed
    grouping = BadgeGrouping.create!(name: "Site presentation", position: 20)
    host = described_class.find("Host")
    host.update!(badge_grouping: grouping)
    custom =
      Fabricate(
        :badge,
        badge_grouping: BadgeGrouping.find_by(name: "Live"),
        enabled: true,
        system: false,
      )

    Live::BadgeGranterHooks.disable_all!
    expect(host.reload.enabled).to eq(false)
    expect(custom.reload.enabled).to eq(true)
    Live::BadgeGranterHooks.enable_all!
    expect(host.reload.enabled).to eq(true)
  end

  it "never grants a custom Host badge when the plugin's name is occupied" do
    Badge
      .where(name: "Host")
      .each do |badge|
        UserBadge.where(badge_id: badge.id).delete_all
        badge.destroy!
      end
    custom = Fabricate(:badge, name: "Host", system: false)
    user = Fabricate(:user)
    seed

    Live::BadgeGranterHooks.on_room_create(user)
    expect(UserBadge.where(badge: custom, user: user)).to be_empty
  end

  it "retains a legitimate legacy badge's local ID and disabled state" do
    seed
    badge = described_class.find("Rookie")
    badge.update_columns(
      plugin_badge_key: nil,
      enabled: false,
      query: badge.query.gsub("live_sessions", "voice_sessions"),
    )
    award = Fabricate(:user_badge, badge: badge)

    seed
    expect(described_class.find("Rookie").id).to eq(badge.id)
    expect(badge.reload.enabled).to eq(false)
    expect(award.reload.badge_id).to eq(badge.id)
  end
end
