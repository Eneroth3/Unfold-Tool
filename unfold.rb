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

# Return new vector transformed as a normal.
#
# Transforming a normal vector as a ordinary vector can give it a faulty
# direction if the transformation is non-uniformly scaled or sheared. This
# method assures the vector stays perpendicular to its perpendicular plane
# when a transformation is applied.
#
# @param normal [Geom::Vector3d]
# @param transformation [Geom::Transformation]
#
# @return [Geom::Vector3d]
def transform_as_normal(normal, transformation)
  tangent = normal.axes[0].transform(transformation)
  bi_tangent = normal.axes[1].transform(transformation)
  normal = (tangent * bi_tangent).normalize

  flipped?(transformation) ? normal.reverse : normal
end

# Test if transformation is flipped (mirrored).
#
# @param transformation [Geom::Transformation]
#
# @return [Boolean]
def flipped?(transformation)
  product = transformation.xaxis * transformation.yaxis

  (product % transformation.zaxis).negative?
end

def same_plane?(plane1, plane2)
  plane2[0].on_plane?(plane1) && plane2[1].parallel?(plane1[1])
end

# Unfold model to flat single plane.
# Useful for parts being laser cut or printed on a single piece of paper.

class UnfoldTool
  def initalize
    @hovered_entity = nil
    @start_plane = nil
    @hovered_plane = nil

    # Used for highlighting the hovered face
    # REVIEW: May change UX to select hovered entity for highlighting and draw a
    # square around the cursor to communicate the plane.
    # May use InputPoint and not pickHelper
    @hovered_face = nil
    @hovered_face_transformation = nil
  end

  def activate
    # Try pick a reference plane fro the pre-selection, if its flat.
    @start_plane = plane_from_entities(Sketchup.active_model.selection)
    Sketchup.active_model.selection.clear unless @start_plane
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
        transform_as_normal(@hovered_face.normal, @hovered_face_transformation)
      ]
      # Adjust plane's "origin point" to where the cursor is.
      # This let us fold the geometry the expected way, as there are two ways to
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
        angle = angle_in_plane(rotation_axis, @start_plane[0], @hovered_plane[0]) + Math::PI
        transformation = Geom::Transformation.rotation(*rotation_axis, angle)
        view.model.active_entities.transform_entities(transformation, view.model.selection)
      end
    end

    # Add clicked thing to selection
    # FIXME: When raw face gets rotated, it is destroyed and re-created, losing the object reference.
    view.model.selection.add(@hovered_entity)

    # For next click, the just now clicked plane will be the starting plane for
    # the rotation.
    @start_plane = @hovered_plane
  end

  private

  # @return [nil, Array(Geom::Point3d.new, Geom::Vector3d)]
  #   nil if not flat.
  def plane_from_entities(entities)
    planes = []
    traverse(entities) do |face, transformation|
      next unless face.is_a?(Sketchup::Face)

      # Use face center point rather than arbitrary vertex as plane's point.
      # This allow us to later fold n the expected direction.
      point = face.bounds.center.project_to_plane(face.plane).transform(transformation)
      normal = transform_as_normal(face.normal, transformation)
      planes << [point, normal]
    end

    return if planes.empty?
    return unless planes[1..-1].all? { |p| same_plane?(planes.first, p) }

    planes.first
  end

  def traverse(entities, transformation = IDENTITY, backtrace = [], &block)
    entities.each do |entity|
      yield entity, transformation, backtrace
      if entity.respond_to?(:definition)
        traverse(entity.definition.entities, entity.transformation * transformation, backtrace + [entity], &block)
      end
    end
  end
end

Sketchup.active_model.select_tool(UnfoldTool.new)
