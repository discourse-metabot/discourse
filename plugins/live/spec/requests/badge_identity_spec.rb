# frozen_string_literal: true

RSpec.describe "Live badge seeding", type: :request do
  it "keeps a custom Patron badge accessible with Live disabled" do
    Badge.where(name: "Patron").destroy_all
    patron =
      Fabricate(
        :badge,
        name: "Patron",
        enabled: true,
        system: false,
        description: "Manually awarded supporter",
      )
    award = Fabricate(:user_badge, badge: patron)
    SiteSetting.live_enabled = false

    get "/badges/#{patron.id}/patron.json"
    expect(response.status).to eq(200)

    SeedFu.seed(Rails.root.join("plugins/live/db/fixtures"))

    get "/badges/#{patron.id}/patron.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("badge", "description")).to eq("Manually awarded supporter")
    expect(award.reload.badge_id).to eq(patron.id)
    expect(patron.reload.enabled).to eq(true)
    expect(patron.system).to eq(false)
    expect(patron.query).to be_nil
  end
end
