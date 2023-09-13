# Calculate angle between two points, as seen along an axis.
# Can return negative angles unlike Ruby APIs Vector3d.angleBetween method
#
# @param axis [Array(Geom::Point3d, Geom::Vector3d)]
# @param point1 [Geom::Point3d]
# @param point2 [Geom::Point3d]
#
# @return [Float] Angle in radians.
def angle_in_plane(axis, point1, point2)
  # Based on method from Eneroth 3D Rotate.

  point1 = point1.project_to_plane(axis)
  point2 = point2.project_to_plane(axis)
  vector1 = point1 - axis[0]
  vector2 = point2 - axis[0]

  angle = vector1.angle_between(vector2)

  vector1 * vector2 % axis[1] > 0 ? angle : -angle
end

# Unfold model to flat single plane.
# Useful for parts being laser cut or printed on a single piece of paper.

# REVIEW: Starting with only component/group support.
# Add raw face support later.

class UnfoldTool
  def initalize
    @hovered_entity = nil
    @hovered_plane = nil
    @start_plane = nil
    
    # Used for highlighting the hovered face
    # REVIEW: May change UX to select hovered entity for highlighting and draw a
    # square around the cursor to communicate the plane.
    # May use InputPoint and not pickHelper
    @hovered_face = nil
    @hovered_face_transformation = nil
  end

  def activate
    # This tool cannot have a pre-selection.
    # The user needs to pick a plane, not just an entity.
    Sketchup.active_model.selection.clear
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
        # TODO: Use transform as normal method as transformation may be sheared.
        @hovered_face.normal.transform(@hovered_face_transformation)
      ]
      # Adjust plane's origin point to where the cursor is.
      # This let us fold the geometry the right way, as there are two ways to
      # fold it onto the plane.
      ray = view.pickray(x, y)
      @hovered_plane[0] = Geom.intersect_line_plane(ray, @hovered_plane)
    end

    view.invalidate
  end

  def onLButtonUp(_flags, _x, _y, view)
    return unless @hovered_entity && @hovered_plane
    
    # If something has already been selected, fold it to the clicked plane.
    unless view.model.selection.empty?
      rotation_axis = Geom.intersect_plane_plane(@start_plane, @hovered_plane)
      # Unless its already on that plane.
      if rotation_axis
        angle = angle_in_plane(rotation_axis, @start_plane[0], @hovered_plane[0])
        transformation = Geom::Transformation.rotation(*rotation_axis, angle)
        view.model.active_entities.transform_entities(transformation, view.model.selection)
      end
    end

    # Add clicked thing to selection
    view.model.selection.add(@hovered_entity)
    
    # For next click, the just now clicked plane will be the starting plane for
    # the rotation.
    @start_plane = @hovered_plane
  end
end

Sketchup.active_model.select_tool(UnfoldTool.new)
