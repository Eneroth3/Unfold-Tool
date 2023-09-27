# frozen_string_literal: true

module Eneroth
  module UnfoldTool
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"
    Sketchup.require "#{PLUGIN_ROOT}/entities_helper"

    # Tool for unfolding entities to a single plane.
    #
    # Whereas many SketchUp tool have several distinct stages or phases (first
    # click, second click, third click...) this only has one stage: rotate the
    # selection to the plane of the clicked face and then add it to the
    # selection. If activated without a selection (or a selection that isn't
    # planar and therefore invalid) the clicked face (or its parent container)
    # is simply just added to the selection, and the rotating starts with the
    # next click.
    class Tool
      # Create Tool object.
      def initalize
        @hovered_entity = nil
        @start_plane = nil
        @hovered_plane = nil

        # Used for highlighting the hovered face
        @hovered_face = nil
        @hovered_face_transformation = nil

        # Keep track of these things to handle special case of holding Alt to
        # rotate clicked entity to selection's plane and not the other way
        # around.
        @old_selection = nil
        @transformation = nil
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def activate
        # Try pick a reference plane fro the pre-selection, if its flat.
        @start_plane = EntitiesHelper.plane_from_entities(Sketchup.active_model.selection)
        if @start_plane
          # Adjust plane's "origin" point to somewhere inside the selection, not an
          # outer vertex.
          # This let us fold the geometry the expected way, as there are two ways to
          # fold it onto the plane.
          @start_plane[0] = Sketchup.active_model.selection.first.bounds.center.project_to_plane(@start_plane)
        end

        Sketchup.active_model.selection.clear unless @start_plane

        update_statusbar
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def deactivate(view)
        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def draw(view)
        return unless @hovered_face

        corners = @hovered_face.outer_loop.vertices.map { |v| v.position.transform(@hovered_face_transformation) }

        view.drawing_color = "Magenta"
        view.line_width = 4
        view.draw(GL_LINE_LOOP, corners)
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def getExtents
        # We only draw within the existing model bounds to highlight a hovered
        # face. This method isn't technically needed but Rubocop shouts as us if
        # we don't have it.
        Sketchup.active_model.bounds
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def getInstructorContentDirectory
        "#{PLUGIN_ROOT}/instructor/unfold_tool.html"
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onCancel(_reason, view)
        # The grouping and exploding done when rotating means the objects are
        # lost from the selection when undoing.
        # Might as well empty the whole selection and reset the tool.
        view.model.selection.clear
        @hovered_entity = nil
        @start_plane = nil
        @hovered_plane = nil
        @hovered_face = nil
        @hovered_face_transformation = nil
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onMouseMove(_flags, x, y, view)
        pick_helper = view.pick_helper
        pick_helper.do_pick(x, y)

        @hovered_entity = pick_helper.best_picked
        @hovered_plane = nil

        @hovered_face = view.pick_helper.picked_face
        if @hovered_face
          pick_index = pick_helper.count.times.find { |i| pick_helper.leaf_at(i) == @hovered_face }
          @hovered_face_transformation = pick_helper.transformation_at(pick_index)

          @hovered_plane = [
            @hovered_face.vertices.first.position.transform(@hovered_face_transformation),
            GeomHelper.transform_as_normal(@hovered_face.normal, @hovered_face_transformation)
          ]
          # Adjust plane's "origin point" to where the cursor is.
          # This let us fold the geometry the expected way, as there are two ways to
          # fold it onto the plane.
          ray = view.pickray(x, y)
          @hovered_plane[0] = Geom.intersect_line_plane(ray, @hovered_plane)
        end

        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonUp(flags, _x, _y, view)
        return unless @hovered_entity && @hovered_plane

        alt_down = flags & ALT_MODIFIER_MASK == ALT_MODIFIER_MASK

        # If something has already been selected, fold it to the clicked plane.
        unless view.model.selection.empty?
          # If Alt is held down, temporarily swap selection and hovered entity.
          # Useful to pick up a branching face along the way when unfolding
          # several faces.
          pre_rotate_swap(view) if alt_down
          rotate_selection(view)
          post_rotate_swap(view) if alt_down
        end

        view.model.selection.add(@hovered_entity)

        # For the next click, the just now clicked plane will be the starting
        # plane for the rotation.
        @start_plane = @hovered_plane

        update_statusbar
        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def resume(view)
        view.invalidate
        update_statusbar
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def suspend(view)
        view.invalidate
      end

      private

      # Set the SketchUp statusbar text.
      def update_statusbar
        alt_key_name = Sketchup.platform == :platform_win ? "Alt" : "Command"

        Sketchup.status_text =
          if Sketchup.active_model.selection.empty?
            "Select a face, a group or component to fold."
          else
            "Click face to fold selection to its plane. "\
            "#{alt_key_name} = Fold clicked face to selection."
          end
      end

      # Rotate the selection onto the picked plane.
      #
      # @param view [Sketchup::View]
      def rotate_selection(view)
        rotation_axis = Geom.intersect_plane_plane(@start_plane, @hovered_plane)

        # Already on the right plane.
        return unless rotation_axis

        angle = GeomHelper.angle_in_plane(rotation_axis, @start_plane[0], @hovered_plane[0]) + Math::PI
        @transformation = Geom::Transformation.rotation(*rotation_axis, angle)

        view.model.start_operation("Unfold", true)
        # HACK: Temporarily group geometry being moved to avoid adjacent
        # geometry to be dragged along, and to prevent faces from being
        # triangulated and re-merged, losing them from the selection.
        temp_group = view.model.active_entities.add_group(view.model.selection)
        view.model.active_entities.transform_entities(@transformation, temp_group)
        view.model.selection.add(temp_group.explode.grep(Sketchup::Drawingelement))
        view.model.commit_operation
      end

      # Swap selection and clicked face before a rotation.
      #
      # @param view [Sketchup::View]
      def pre_rotate_swap(view)
        @start_plane, @hovered_plane = @hovered_plane, @start_plane
        @old_selection = view.model.selection.to_a
        view.model.selection.clear
        view.model.selection.add(@hovered_entity)
      end

      # Swap back selection and clicked face after a rotation.
      #
      # @param view [Sketchup::View]
      def post_rotate_swap(view)
        # Should only be one object selected.
        @hovered_entity = view.model.selection.first
        # Extra safe guard as faces can be split and merged and deleted when moved.
        @hovered_face = nil if @hovered_face.deleted?
        view.model.selection.add(@old_selection.select(&:valid?))
        # Make sure outline of clicked face doesn't linger on old location.
        @hovered_face_transformation = @transformation * @hovered_face_transformation
      end
    end
  end
end
