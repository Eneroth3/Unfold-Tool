module Eneroth
  module UnfoldTool
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"
    Sketchup.require "#{PLUGIN_ROOT}/entities_helper"

    # Tool for unfolding entities to a single plane.
    class UnfoldTool
      def initalize
        @hovered_entity = nil
        @start_plane = nil
        @hovered_plane = nil

        # Used for highlighting the hovered face
        @hovered_face = nil
        @hovered_face_transformation = nil
      end

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

      def draw(view)
        return unless @hovered_face

        corners = @hovered_face.outer_loop.vertices.map { |v| v.position.transform(@hovered_face_transformation) }

        view.drawing_color = "Magenta"
        view.line_width = 4
        view.draw(GL_LINE_LOOP, corners)
      end

      def onMouseMove(flags, x, y, view)
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

      def onLButtonUp(flags, _x, _y, view)
        return unless @hovered_entity && @hovered_plane

        alt_down = flags & ALT_MODIFIER_MASK  == ALT_MODIFIER_MASK

        # If something has already been selected, fold it to the clicked plane.
        rotate_selection(view, alt_down) unless view.model.selection.empty?

        view.model.selection.add(@hovered_entity)

        # For the next click, the just now clicked plane will be the starting
        # plane for the rotation.
        @start_plane = @hovered_plane

        update_statusbar
        view.invalidate
      end

      def resume(view)
        update_statusbar
      end

      # REVIEW: Hold modifier key (Alt?) to fold the clicked entity towards the
      # selection, instead of the other way around. Use to pick up flaps along the
      # way.

      private

      def update_statusbar
        Sketchup.status_text =
          if Sketchup.active_model.selection.empty?
            "Select a face, a group or component."
          else
            "Click face to fold selection to its plane." #  Alt = Fold clicked face to selection.
          end
      end

      # Rotate the selection onto the picked plane.
      #
      # @param view [Sketchup::View]
      def rotate_selection(view, swapped)
        # Special case of rotating the clicked entity to the selection, not the
        # other way around.
        if swapped
          @start_plane, @hovered_plane = @hovered_plane, @start_plane
          old_selection = view.model.selection.to_a
          view.model.selection.clear
          view.model.selection.add(@hovered_entity)
        end

        rotation_axis = Geom.intersect_plane_plane(@start_plane, @hovered_plane)

        # Already on the right plane.
        return unless rotation_axis

        angle = GeomHelper.angle_in_plane(rotation_axis, @start_plane[0], @hovered_plane[0]) + Math::PI
        transformation = Geom::Transformation.rotation(*rotation_axis, angle)

        view.model.start_operation("Unfold", true)
        # HACK: Temporarily group geometry being moved to avoid adjacent
        # geometry to be dragged along, and to prevent faces from being
        # triangulated and re-merged, losing them from the selection.
        temp_group = view.model.active_entities.add_group(view.model.selection)
        view.model.active_entities.transform_entities(transformation, temp_group)
        view.model.selection.add(temp_group.explode.grep(Sketchup::Drawingelement))
        view.model.commit_operation

        # Special case of rotating the clicked entity to the selection, not the
        # other way around.
        if swapped
          # Should only be one object selected.
          @hovered_entity = view.model.selection.first
          view.model.selection.clear
          view.model.selection.add(old_selection)
          # Make sure preview is clicked face doesn't linger in old location.
          @hovered_face_transformation *= transformation
        end
      end
    end

    # TODO: Make a toolbar
    menu = UI.menu("Plugins")
    menu.add_item(EXTENSION.name) { Sketchup.active_model.select_tool(UnfoldTool.new) }

    # Reload extension.
    #
    # @param clear_console [Boolean] Whether console should be cleared.
    # @param undo [Boolean] Whether last operation should be undone.
    #
    # @return [void]
    def self.reload(clear_console = true, undo = false)
      # Hide warnings for already defined constants.
      verbose = $VERBOSE
      $VERBOSE = nil
      Dir.glob(File.join(PLUGIN_ROOT, "**/*.{rb,rbe}")).each { |f| load(f) }
      $VERBOSE = verbose

      # Use a timer to make call to method itself register to console.
      # Otherwise the user cannot use up arrow to repeat command.
      UI.start_timer(0) { SKETCHUP_CONSOLE.clear } if clear_console

      Sketchup.undo if undo

      nil
    end
  end
end
