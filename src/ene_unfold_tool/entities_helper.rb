module Eneroth
  module UnfoldTool
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"

    # Helper methods to deal with SketchUp Entities collections.
    module EntitiesHelper
      # Extract plane from entities. Works on raw faces and faces in groups or
      # components.
      #
      # @param entities [Sketchup::Entities, Sketchup::Selection, Array<Sketchup::Drawingelement>]
      #
      # @return [Array(Geom::Point3d.new, Geom::Vector3d), nil]
      #  `nil` if not flat.
      def self.plane_from_entities(entities)
        planes = []
        traverse(entities) do |face, transformation|
          next unless face.is_a?(Sketchup::Face)

          planes << [
            face.vertices.first.position.transform(transformation),
            GeomHelper.transform_as_normal(face.normal, transformation)
          ]
        end

        return if planes.empty?
        return unless planes[1..-1].all? { |p| GeomHelper.same_plane?(planes.first, p) }

        planes.first
      end

      # Iterate recursively over entities and yield for each entity.
      #
      # @param entities [Sketchup::Entities, Sketchup::Selection, Array<Sketchup::Drawingelement>]
      # @param transformation [Geom::Transformation]
      # @param backtrace [Array<Sketchup::Group, Sketchup::ComponentInstance>]
      #
      # @yieldparam entity [Sketchup::Drawingelement]
      # @yieldparam transformation [Geom::Transformation]
      # @yieldparam backtrace [Array<Sketchup::Group, Sketchup::ComponentInstance>]
      def self.traverse(entities, transformation = IDENTITY, backtrace = [], &block)
        entities.each do |entity|
          yield entity, transformation, backtrace
          if entity.respond_to?(:definition)
            traverse(entity.definition.entities, entity.transformation * transformation, backtrace + [entity], &block)
          end
        end
      end
    end
  end
end
