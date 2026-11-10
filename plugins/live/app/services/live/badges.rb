# frozen_string_literal: true

module Live
  module Badges
    # Explicit keys are permanent. Display names may change independently.
    KEYS = {
      "Mic Check" => "live:mic_check",
      "Rookie" => "live:rookie",
      "Chatterbox" => "live:chatterbox",
      "Silver Tongue" => "live:silver_tongue",
      "Icebreaker" => "live:icebreaker",
      "Social Butterfly" => "live:social_butterfly",
      "Life of the Party" => "live:life_of_the_party",
      "Familiar Face" => "live:familiar_face",
      "Inner Circle" => "live:inner_circle",
      "Partners in Crime" => "live:partners_in_crime",
      "Explorer" => "live:explorer",
      "Nomad" => "live:nomad",
      "Omnipresent" => "live:omnipresent",
      "Live Patron" => "live:patron",
      "Barfly" => "live:barfly",
      "The Mayor" => "live:the_mayor",
      "Host" => "live:host",
      "Crowd Puller" => "live:crowd_puller",
      "Master of Ceremonies" => "live:master_of_ceremonies",
      "Plus One" => "live:plus_one",
      "Connector" => "live:connector",
      "People Magnet" => "live:people_magnet",
      "Night Owl" => "live:night_owl",
      "Early Bird" => "live:early_bird",
      "Packed House" => "live:packed_house",
      "Weekend Warrior" => "live:weekend_warrior",
      "Marathoner" => "live:marathoner",
    }.freeze

    def self.seed(name, &definition)
      # Never adopt an old Patron: a genuine plugin badge and a clobbered custom
      # badge are indistinguishable. Leave that ID, definition and awards alone;
      # an administrator must review it rather than guessing its original data.
      expected = Badge.new
      definition.call(expected)
      # Explicit historical variant of this trusted fixture, not normalization
      # of a candidate SQL query (which could change literals or comments).
      voice_query =
        expected
          .query
          &.gsub(/\blive_(sessions|co_presences|rooms)\b/) { "voice_#{Regexp.last_match(1)}" }
      Badge.seed_plugin(
        KEYS.fetch(name),
        name: name,
        legacy_groupings: %w[Voice Live],
        legacy_queries: [voice_query],
        &definition
      )
    end

    def self.owned
      Badge.where(plugin_badge_key: KEYS.values)
    end

    def self.find(name)
      owned.find_by(plugin_badge_key: KEYS.fetch(name))
    end
  end
end
