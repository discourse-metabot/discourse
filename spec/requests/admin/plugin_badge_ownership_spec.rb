# frozen_string_literal: true

RSpec.describe Admin::BadgesController do
  fab!(:admin)
  before { sign_in(admin) }

  it "does not permit plugin ownership on badge creation" do
    post "/admin/badges.json",
         params: {
           name: "Synthetic custom badge",
           badge_type_id: BadgeType::Bronze,
           plugin_badge_key: "synthetic:admin_created",
         }
    expect(response.status).to eq(200)
    expect(Badge.find_by!(name: "Synthetic custom badge").plugin_badge_key).to be_nil
  end

  it "does not permit attaching ownership to a custom badge" do
    badge = Fabricate(:badge)
    put "/admin/badges/#{badge.id}.json", params: { plugin_badge_key: "synthetic:admin_updated" }
    expect(response.status).to eq(200)
    expect(badge.reload.plugin_badge_key).to be_nil
  end

  it "does not permit attaching plugin ownership to a core badge" do
    badge = Badge.find(Badge::Reader)
    put "/admin/badges/#{badge.id}.json", params: { plugin_badge_key: "synthetic:core" }
    expect(response.status).to eq(200)
    expect(badge.reload.plugin_badge_key).to be_nil
  end
end
