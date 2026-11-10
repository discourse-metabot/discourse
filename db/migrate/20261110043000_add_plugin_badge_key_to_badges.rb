# frozen_string_literal: true

class AddPluginBadgeKeyToBadges < ActiveRecord::Migration[8.1]
  def change
    add_column :badges, :plugin_badge_key, :string
    add_index :badges, :plugin_badge_key, unique: true
  end
end
