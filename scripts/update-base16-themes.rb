#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "yaml"

unless ARGV.length == 2
  warn "Usage: update-base16-themes.rb /path/to/tinted-theming/schemes Hashlight/Resources/Base16Themes.json"
  exit 64
end

source_root = File.expand_path(ARGV[0])
output_path = File.expand_path(ARGV[1])
schemes_path = File.join(source_root, "base16")
required_colors = (0..15).map { |index| format("base%02X", index) }

unless Dir.exist?(schemes_path)
  warn "Missing Base16 schemes directory: #{schemes_path}"
  exit 66
end

themes = Dir.glob(File.join(schemes_path, "*.yaml")).sort.each_with_object([]) do |path, result|
  data = YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
  next unless data.is_a?(Hash) && data["system"] == "base16"
  next unless %w[light dark].include?(data["variant"])

  palette = data["palette"]
  next unless palette.is_a?(Hash) && required_colors.all? { |key| palette[key].is_a?(String) }

  result << {
    "id" => File.basename(path, ".yaml"),
    "name" => data.fetch("name"),
    "author" => data.fetch("author", "Unknown"),
    "variant" => data.fetch("variant"),
    "palette" => required_colors.to_h { |key| [key, palette.fetch(key)] }
  }
end

revision, status = Open3.capture2("git", "-C", source_root, "rev-parse", "HEAD")
revision = "unknown" unless status.success?

catalog = {
  "source" => {
    "repository" => "https://github.com/tinted-theming/schemes",
    "revision" => revision.strip
  },
  "themes" => themes.sort_by { |theme| [theme.fetch("name").downcase, theme.fetch("id")] }
}

FileUtils.mkdir_p(File.dirname(output_path)) unless Dir.exist?(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(catalog) + "\n")
puts "Wrote #{themes.length} Base16 themes to #{output_path}"
