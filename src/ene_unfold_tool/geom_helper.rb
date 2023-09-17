# frozen_string_literal: true

module Eneroth
  module UnfoldTool
    # Various lierar algebra thingies not present in the Ruby API Geom module.
    module GeomHelper
      # Calculate angle between two points, as seen along an axis.
      # Can return negative angles unlike Ruby APIs Vector3d.angleBetween method
      #
      # @param axis [Array(Geom::Point3d, Geom::Vector3d)]
      # @param point1 [Geom::Point3d]
      # @param point2 [Geom::Point3d]
      #
      # @return [Float] Angle in radians.
      def self.angle_in_plane(axis, point1, point2)
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
      def self.transform_as_normal(normal, transformation)
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
      def self.flipped?(transformation)
        product = transformation.xaxis * transformation.yaxis

        (product % transformation.zaxis).negative?
      end

      # Test if two planes are the same.
      #
      # @param plane1 [Array(Geom::Point3d.new, Geom::Vector3d)]
      # @param plane2 [Array(Geom::Point3d.new, Geom::Vector3d)]
      #
      # @return [Boolean]
      def self.same_plane?(plane1, plane2)
        plane2[0].on_plane?(plane1) && plane2[1].parallel?(plane1[1])
      end
    end
  end
end
