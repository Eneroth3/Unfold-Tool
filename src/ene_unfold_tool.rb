# frozen_string_literal: true

require "extensions.rb"

# Eneroth Extensions
module Eneroth
  # Eneroth Unfold Tool
  module UnfoldTool
    path = __FILE__.dup
    path.force_encoding("UTF-8") if path.respond_to?(:force_encoding)

    # Identifier for this extension.
    PLUGIN_ID = File.basename(path, ".*")

    # Root directory of this extension.
    PLUGIN_ROOT = File.join(File.dirname(path), PLUGIN_ID)

    # Extension object for this extension.
    EXTENSION = SketchupExtension.new(
      "Eneroth Unfold Tool",
      File.join(PLUGIN_ROOT, "main")
    )

    EXTENSION.creator     = "Eneroth"
    EXTENSION.description = "Unfold to single plane. Useful for paper models and laser cutting."
    EXTENSION.version     = "1.0.2"
    EXTENSION.copyright   = "2023, #{EXTENSION.creator}"
    Sketchup.register_extension(EXTENSION, true)
  end
end
