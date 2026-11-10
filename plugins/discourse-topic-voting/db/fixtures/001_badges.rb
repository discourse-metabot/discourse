# frozen_string_literal: true

[
  ["discourse-topic-voting:daydreamer", "Daydreamer", BadgeType::Bronze, 1, false],
  ["discourse-topic-voting:brainstormer", "Brainstormer", BadgeType::Silver, 5, true],
  ["discourse-topic-voting:innovator", "Innovator", BadgeType::Silver, 15, true],
  ["discourse-topic-voting:visionary", "Visionary", BadgeType::Gold, 25, true],
].each do |key, name, level, count, allow_title|
  Badge.seed_plugin(key, name: name) do |badge|
    badge.default_icon = "vote-up-filled"
    badge.badge_type_id = level
    badge.default_badge_grouping_id = BadgeGrouping::Community
    badge.query = DiscourseTopicVoting::BadgeQueries.for_threshold(count)
    badge.listable = true
    badge.target_posts = true
    badge.multiple_grant = true
    badge.default_enabled = true
    badge.default_allow_title = allow_title
    badge.trigger = Badge::Trigger::None
    badge.auto_revoke = true
    badge.show_posts = true
  end
end
