# cython: language_level=3, embedsignature=True, auto_pickle=False
# """Optimised Vector object."""
from libc cimport math
cimport cython

# Lightweight struct just holding the three values.
# Used for subcalculations.
cdef struct vec_t:
    double x
    double y
    double z

cdef inline Vec _vector(double x, double y, double z):
    """Make a Vector directly."""
    cdef Vec vec = Vec.__new__(Vec)
    vec.val.x = x
    vec.val.y = y
    vec.val.z = z
    return vec

cdef object _vector_make
from srctools.vec import _mk as _vector_make

cdef unsigned char _parse_vec_str(vec_t *vec, object value, double x, double y, double z) except False:
    cdef unicode str_x, str_y, str_z

    if isinstance(value, Vec):
        vec.x = (<Vec>value).val.x
        vec.y = (<Vec>value).val.y
        vec.z = (<Vec>value).val.z
        return True

    try:
        str_x, str_y, str_z = (<unicode?>value).split(' ')
    except ValueError:
        vec.x = x
        vec.y = y
        vec.z = z
        return True

    if str_x[0] in '({[<':
        str_x = str_x[1:]
    if str_z[-1] in ')}]>':
        str_z = str_z[:-1]
    try:
        vec.x = float(str_x)
        vec.y = float(str_y)
        vec.z = float(str_z)
    except ValueError:
        vec.x = x
        vec.y = y
        vec.z = z
    return True

cdef inline unsigned char _conv_vec(
    vec_t *result,
    object vec,
    bint scalar,
) except False:
    """Convert some object to a unified Vector struct. 
    
    If scalar is True, allow int/float to set all axes.
    """
    if isinstance(vec, Vec):
        result.x = (<Vec>vec).val.x
        result.y = (<Vec>vec).val.y
        result.z = (<Vec>vec).val.z
    elif isinstance(vec, float) or isinstance(vec, int):
        if scalar:
            result.x = result.y = result.z = vec
        else:
            # No need to do argument checks.
            raise TypeError('Cannot use scalars here.')
    elif isinstance(vec, tuple):
        result.x, result.y, result.z = <tuple>vec
    else:
        try:
            result.x = vec.x
            result.y = vec.y
            result.z = vec.z
        except AttributeError:
            raise TypeError(f'{type(vec)} is not a Vec-like object!')
    return True

DEF PI = 3.141592653589793238462643383279502884197
# Multiply to convert.
DEF rad_2_deg = 180 / PI
DEF deg_2_rad = PI / 180.0

@cython.final
cdef class VecIter:
    """Implements iter(Vec)."""
    cdef Vec vec
    cdef unsigned char index

    def __cinit__(self, Vec vec not None):
        self.vec = vec
        self.index = 0

    def __iter__(self):
        return self

    def __next__(self):
        if self.index == 3:
            raise StopIteration
        self.index += 1
        if self.index == 1:
            return self.vec.val.x
        if self.index == 2:
            return self.vec.val.y
        if self.index == 3:
            # Drop our reference.
            ret = self.vec.val.z
            self.vec = None
            return ret


# Lots of temporaries are expected.
@cython.freelist(16)
@cython.final
cdef class Vec:
    """A 3D Vector. This has most standard Vector functions.

    Many of the functions will accept a 3-tuple for comparison purposes.
    """
    # This is a sub-struct, so we can pass pointers to it to other
    # functions.
    cdef vec_t val

    @property
    def x(self):
        return self.val.x

    @x.setter
    def x(self, value):
        self.val.x = value

    @property
    def y(self):
        return self.val.y

    @y.setter
    def y(self, value):
        self.val.y = value

    @property
    def z(self):
        return self.val.z

    @z.setter
    def z(self, value):
        self.val.z = value

    def __init__ (
        self,
        x=0.0,
        y=0.0,
        z=0.0,
    ):
        """Create a Vector.

        All values are converted to Floats automatically.
        If no value is given, that axis will be set to 0.
        An iterable can be passed in (as the x argument), which will be
        used for x, y, and z.
        """
        cdef tuple tup
        if isinstance(x, float) or isinstance(x, int):
            self.val.x = x
            self.val.y = y
            self.val.z = z
        elif isinstance(x, Vec):
            self.val.x = (<Vec>x).val.x
            self.val.y = (<Vec>x).val.y
            self.val.z = (<Vec>x).val.z
        elif isinstance(x, tuple):
            tup = <tuple>x
            if len(tup) >= 1:
                self.val.x = tup[0]
            else:
                self.val.x = 0

            if len(tup) >= 2:
                self.val.y = tup[1]
            else:
                self.val.y = y

            if len(tup) >= 3:
                self.val.z = tup[3]
            else:
                self.val.z = z

        else:
            it = iter(x)
            try:
                self.val.x = next(it)
            except StopIteration:
                self.val.x = 0
                self.val.y = y
                self.val.z = z
                return

            try:
                self.val.y = next(it)
            except StopIteration:
                self.val.y = y
                self.val.z = z
                return

            try:
                self.val.z = next(it)
            except StopIteration:
                self.val.z = z

    def copy(self):
        """Create a duplicate of this vector."""
        return _vector(self.val.x, self.val.y, self.val.z)

    def __copy__(self):
        """Create a duplicate of this vector."""
        return _vector(self.val.x, self.val.y, self.val.z)

    def __reduce__(self):
        return _vector_make, (self.val.x, self.val.y, self.val.z)

    @classmethod
    def from_str(cls, value, double x=0, double y=0, double z=0):
        """Convert a string in the form '(4 6 -4)' into a Vector.

        If the string is unparsable, this uses the defaults (x,y,z).
        The string can start with any of the (), {}, [], <> bracket
        types, or none.

        If the value is already a vector, a copy will be returned.
        """
        cdef Vec vec = Vec.__new__(Vec)
        _parse_vec_str(&vec.val, value, x, y, z)
        return vec

    @staticmethod
    @cython.boundscheck(False)
    def with_axes(*args) -> 'Vec':
        """Create a Vector, given a number of axes and corresponding values.

        This is a convenience for doing the following:
            vec = Vec()
            vec[axis1] = val1
            vec[axis2] = val2
            vec[axis3] = val3
        The magnitudes can also be Vectors, in which case the matching
        axis will be used from the vector.
        """
        cdef Py_ssize_t arg_count = len(args)
        if arg_count not in (2, 4, 6):
            raise TypeError(
                f'Vec.with_axis() takes 2, 4 or 6 positional arguments '
                f'but {arg_count} were given'
            )

        cdef Vec vec = Vec.__new__(Vec)
        cdef unicode axis
        cdef unsigned char i
        for i in range(0, arg_count, 2):
            axis = args[i]
            axis_val = args[i+1]
            if axis == 'x':
                if isinstance(axis_val, Vec):
                    vec.val.x = (<Vec>axis_val).val.x
                else:
                    vec.val.x = axis_val
            elif axis == 'y':
                if isinstance(axis_val, Vec):
                    vec.val.y = (<Vec>axis_val).val.y
                else:
                    vec.val.y = axis_val
            elif axis == 'z':
                if isinstance(axis_val, Vec):
                    vec.val.z = (<Vec>axis_val).val.z
                else:
                    vec.val.z = axis_val
            else:
                raise ValueError(f'Invalid axis {axis!r}!')

        return vec

    @staticmethod
    def bbox(*points: Vec) -> 'Tuple[Vec, Vec]':
        """Compute the bounding box for a set of points.

        Pass either several Vecs, or an iterable of Vecs.
        Returns a (min, max) tuple.
        """
        cdef Vec bbox_min = Vec.__new__(Vec)
        cdef Vec bbox_max = Vec.__new__(Vec)
        cdef Vec sing_vec
        cdef vec_t vec
        cdef Py_ssize_t i
        # Allow passing a single iterable, but also handle a single Vec.
        # The error messages match those produced by min()/max().

        if len(points) == 1:
            if isinstance(points[0], Vec):
                # Special case, don't iter over the vec, just copy.
                sing_vec = <Vec>points[0]
                bbox_min.val = sing_vec.val
                bbox_max.val = sing_vec.val
                return bbox_min, bbox_max
            points_iter = iter(points[0])
            try:
                first = next(points_iter)
            except StopIteration:
                raise ValueError('Empty iterator!') from None

            _conv_vec(&bbox_min.val, first, scalar=False)
            bbox_max.val = bbox_min.val

            try:
                while True:
                    point = next(points_iter)
                    _conv_vec(&vec, point, scalar=False)

                    if bbox_max.val.x < vec.x:
                        bbox_max.val.x = vec.x

                    if bbox_max.val.y < vec.y:
                        bbox_max.val.y = vec.y

                    if bbox_max.val.z < vec.z:
                        bbox_max.val.z = vec.z

                    if bbox_min.val.x > vec.x:
                        bbox_min.val.x = vec.x

                    if bbox_min.val.y > vec.y:
                        bbox_min.val.y = vec.y

                    if bbox_min.val.z > vec.z:
                        bbox_min.val.z = vec.z
            except StopIteration:
                pass
        elif len(points) == 0:
            raise TypeError(
                'Vec.bbox() expected at '
                'least 1 argument, got 0.'
            )
        else:
            # Tuple-specific.
            _conv_vec(&bbox_min.val, points[0], scalar=False)
            bbox_max.val = bbox_min.val

            for i in range(1, len(points)):
                point = points[i]
                _conv_vec(&vec, point, scalar=False)

                if bbox_max.val.x < vec.x:
                    bbox_max.val.x = vec.x

                if bbox_max.val.y < vec.y:
                    bbox_max.val.y = vec.y

                if bbox_max.val.z < vec.z:
                    bbox_max.val.z = vec.z

                if bbox_min.val.x > vec.x:
                    bbox_min.val.x = vec.x

                if bbox_min.val.y > vec.y:
                    bbox_min.val.y = vec.y

                if bbox_min.val.z > vec.z:
                    bbox_min.val.z = vec.z

        return bbox_min, bbox_max


    def axis(self) -> str:
        """For a normal vector, return the axis it is on."""

        if self.val.x != 0 and self.val.y == 0 and self.val.z == 0:
            return 'x'
        if self.val.x == 0 and self.val.y != 0 and self.val.z == 0:
            return 'y'
        if self.val.x == 0 and self.val.y == 0 and self.val.z != 0:
            return 'z'
        raise ValueError(
            f'({self.val.x}, {self.val.y}, {self.val.z}) is '
            'not an on-axis vector!'
        )

    def to_angle(self, double roll: float=0) -> 'Vec':
        """Convert a normal to a Source Engine angle.

        A +x axis vector will result in a 0, 0, 0 angle. The roll is not
        affected by the direction of the normal.

        The inverse of this is `Vec(x=1).rotate(pitch, yaw, roll)`.
        """
        cdef Vec vec = Vec().__new__(Vec)

        # Pitch is applied first, so we need to reconstruct the x-value.
        cdef double horiz_dist = math.sqrt(self.val.x ** 2 + self.val.y ** 2)

        vec.val.x = rad_2_deg * math.atan2(-self.z, horiz_dist)
        vec.val.y = (math.atan2(self.y, self.x) * rad_2_deg) % 360.0
        vec.val.z = roll

    def rotation_around(self, double rot: float=90) -> 'Vec':
        """For an axis-aligned normal, return the angles which rotate around it."""
        cdef Vec vec = Vec.__new__(Vec)
        vec.val.x = vec.val.y = vec.val.z = 0.0

        if self.val.x != 0 and self.val.y == 0 and self.val.z == 0:
            vec.val.z = math.copysign(rot, self.val.x)
        elif self.val.x == 0 and self.val.y != 0 and self.val.z == 0:
            vec.val.x = math.copysign(rot, self.val.y)
        elif self.val.x == 0 and self.val.y == 0 and self.val.z != 0:
            vec.val.y = math.copysign(rot, self.val.z)
        else:
            raise ValueError(
                f'({self.val.x}, {self.val.y}, {self.val.z}) is '
                'not an on-axis vector!'
            )
        return vec

    def __abs__(self):
        """Performing abs() on a Vec takes the absolute value of all axes."""
        cdef Vec vec = Vec.__new__(Vec)

        vec.val.x = abs(self.val.x)
        vec.val.y = abs(self.val.y)
        vec.val.z = abs(self.val.z)

        return vec

    # Non-in-place operators. Arg 1 may not be a Vec.

    def __add__(obj_a, obj_b):
        """+ operation.

        This additionally works on scalars (adds to all axes).
        """
        cdef vec_t vec_a, vec_b

        try:
            _conv_vec(&vec_a, obj_a, scalar=True)
            _conv_vec(&vec_b, obj_b, scalar=True)
        except (TypeError, ValueError):
            return NotImplemented

        cdef Vec result = Vec.__new__(Vec)
        result.val.x = vec_a.x + vec_b.x
        result.val.y = vec_a.y + vec_b.y
        result.val.z = vec_a.z + vec_b.z
        return result

    def __sub__(obj_a, obj_b):
        """- operation.

        This additionally works on scalars (adds to all axes).
        """
        cdef vec_t vec_a, vec_b

        try:
            _conv_vec(&vec_a, obj_a, scalar=True)
            _conv_vec(&vec_b, obj_b, scalar=True)
        except (TypeError, ValueError):
            return NotImplemented

        cdef Vec result = Vec.__new__(Vec)
        result.val.x = vec_a.x - vec_b.x
        result.val.y = vec_a.y - vec_b.y
        result.val.z = vec_a.z - vec_b.z
        return result

    def __mul__(obj_a, obj_b):
        """Vector * scalar operation."""
        cdef Vec vec = Vec.__new__(Vec)
        cdef double scalar
        # Vector * Vector is disallowed.
        if isinstance(obj_a, (int, float)):
            # scalar * vector
            scalar = obj_a
            _conv_vec(&vec.val, obj_b, scalar=False)
            vec.val.x = scalar * vec.val.x
            vec.val.y = scalar * vec.val.y
            vec.val.z = scalar * vec.val.z
        elif isinstance(obj_b, (int, float)):
            # vector * scalar.
            _conv_vec(&vec.val, obj_a, scalar=False)
            scalar = obj_b
            vec.val.x = vec.val.x * scalar
            vec.val.y = vec.val.y * scalar
            vec.val.z = vec.val.z * scalar

        elif isinstance(obj_a, Vec) and isinstance(obj_b, Vec):
            raise TypeError('Cannot multiply 2 Vectors.')
        else:
            # Both vector-like or vector * something else.
            return NotImplemented
        return vec

    def __truediv__(obj_a, obj_b):
        """Vector / scalar operation."""
        cdef Vec vec = Vec.__new__(Vec)
        cdef double scalar
        # Vector / Vector is disallowed.
        if isinstance(obj_a, (int, float)):
            # scalar / vector
            scalar = obj_a
            _conv_vec(&vec.val, obj_b, scalar=False)
            vec.val.x = scalar / vec.val.x
            vec.val.y = scalar / vec.val.y
            vec.val.z = scalar / vec.val.z
        elif isinstance(obj_b, (int, float)):
            # vector / scalar.
            _conv_vec(&vec.val, obj_a, scalar=False)
            scalar = obj_b
            vec.val.x = vec.val.x / scalar
            vec.val.y = vec.val.y / scalar
            vec.val.z = vec.val.z / scalar

        elif isinstance(obj_a, Vec) and isinstance(obj_b, Vec):
            raise TypeError('Cannot divide 2 Vectors.')
        else:
            # Both vector-like or vector * something else.
            return NotImplemented
        return vec


    def __floordiv__(obj_a, obj_b):
        """Vector // scalar operation."""
        cdef Vec vec = Vec.__new__(Vec)
        cdef double scalar
        # Vector // Vector is disallowed.
        if isinstance(obj_a, (int, float)):
            # scalar // vector
            scalar = obj_a
            _conv_vec(&vec.val, obj_b, scalar=False)
            vec.val.x = scalar // vec.val.x
            vec.val.y = scalar // vec.val.y
            vec.val.z = scalar // vec.val.z
        elif isinstance(obj_b, (int, float)):
            # vector // scalar.
            _conv_vec(&vec.val, obj_a, scalar=False)
            scalar = obj_b
            vec.val.x = vec.val.x // scalar
            vec.val.y = vec.val.y // scalar
            vec.val.z = vec.val.z // scalar

        elif isinstance(obj_a, Vec) and isinstance(obj_b, Vec):
            raise TypeError('Cannot floor-divide 2 Vectors.')
        else:
            # Both vector-like or vector * something else.
            return NotImplemented
        return vec

    def __mod__(obj_a, obj_b):
        """Vector % scalar operation."""
        cdef Vec vec = Vec.__new__(Vec)
        cdef double scalar
        # Vector % Vector is disallowed.
        if isinstance(obj_a, (int, float)):
            # scalar % vector
            scalar = obj_a
            _conv_vec(&vec.val, obj_b, scalar=False)
            vec.val.x = scalar % vec.val.x
            vec.val.y = scalar % vec.val.y
            vec.val.z = scalar % vec.val.z
        elif isinstance(obj_b, (int, float)):
            # vector % scalar.
            _conv_vec(&vec.val, obj_a, scalar=False)
            scalar = obj_b
            vec.val.x = vec.val.x % scalar
            vec.val.y = vec.val.y % scalar
            vec.val.z = vec.val.z % scalar

        elif isinstance(obj_a, Vec) and isinstance(obj_b, Vec):
            raise TypeError('Cannot modulus 2 Vectors.')
        else:
            # Both vector-like or vector * something else.
            return NotImplemented
        return vec

    # In-place operators. Self is always a Vec.

    def __iadd__(self, other: 'Union[Vec, tuple, float]'):
        """+= operation.

        Like the normal one except without duplication.
        """
        cdef vec_t vec_other
        try:
            _conv_vec(&vec_other, other, scalar=True)
        except (TypeError, ValueError):
            return NotImplemented

        self.val.x += vec_other.x
        self.val.y += vec_other.y
        self.val.z += vec_other.z

        return self

    def __isub__(self, other: 'Union[Vec, tuple, float]'):
        """-= operation.

        Like the normal one except without duplication.
        """
        cdef vec_t vec_other
        try:
            _conv_vec(&vec_other, other, scalar=True)
        except (TypeError, ValueError):
            return NotImplemented

        self.val.x -= vec_other.x
        self.val.y -= vec_other.y
        self.val.z -= vec_other.z

        return self

    def __imul__(self, object other: float):
        """*= operation.

        Like the normal one except without duplication.
        """
        cdef double scalar
        if isinstance(other, (int, float)):
            scalar = other
            self.x *= scalar
            self.y *= scalar
            self.z *= scalar
            return self
        elif isinstance(other, Vec):
            raise TypeError("Cannot multiply 2 Vectors.")
        else:
            return NotImplemented

    def __itruediv__(self, other: float):
        """/= operation.

        Like the normal one except without duplication.
        """
        cdef double scalar
        if isinstance(other, (int, float)):
            scalar = other
            self.x /= scalar
            self.y /= scalar
            self.z /= scalar
            return self
        elif isinstance(other, Vec):
            raise TypeError("Cannot divide 2 Vectors.")
        else:
            return NotImplemented

    def __ifloordiv__(self, other: float):
        """//= operation.

        Like the normal one except without duplication.
        """
        cdef double scalar
        if isinstance(other, (int, float)):
            scalar = other
            self.x //= scalar
            self.y //= scalar
            self.z //= scalar
            return self
        elif isinstance(other, Vec):
            raise TypeError("Cannot floor-divide 2 Vectors.")
        else:
            return NotImplemented

    def __imod__(self, other: float):
        """%= operation.

        Like the normal one except without duplication.
        """
        cdef double scalar
        if isinstance(other, (int, float)):
            scalar = other
            self.x %= scalar
            self.y %= scalar
            self.z %= scalar
            return self
        elif isinstance(other, Vec):
            raise TypeError("Cannot modulus 2 Vectors.")
        else:
            return NotImplemented

    def __divmod__(obj_a, obj_b) -> 'Tuple[Vec, Vec]':
        """Divide the vector by a scalar, returning the result and remainder."""
        cdef Vec vec
        cdef Vec res_1 = Vec.__new__(Vec)
        cdef Vec res_2 = Vec.__new__(Vec)
        cdef double other_d

        if isinstance(obj_a, Vec) and isinstance(obj_b, Vec):
            raise TypeError("Cannot divide 2 Vectors.")
        elif isinstance(obj_a, Vec):
            # vec / val
            vec = <Vec>obj_a
            try:
                other_d = <double ?>obj_b
            except TypeError:
                return NotImplemented

            # We put % first, since Cython then produces a 'divmod' error.

            res_2.val.x = vec.val.x % other_d
            res_1.val.x = vec.val.x // other_d
            res_2.val.y = vec.val.y % other_d
            res_1.val.y = vec.val.y // other_d
            res_2.val.z = vec.val.z % other_d
            res_1.val.z = vec.val.z // other_d
        elif isinstance(obj_b, Vec):
            # val / vec
            vec = <Vec>obj_b
            try:
                other_d = <double ?>obj_a
            except TypeError:
                return NotImplemented

            res_2.val.x = other_d % vec.val.x
            res_1.val.x = other_d // vec.val.x
            res_2.val.y = other_d % vec.val.y
            res_1.val.y = other_d // vec.val.y
            res_2.val.z = other_d % vec.val.z
            res_1.val.z = other_d // vec.val.z
        else:
            raise TypeError("Called with non-vectors??")

        return res_1, res_2
    
    def max(self, other):
        """Set this vector's values to the maximum of the two vectors."""
        cdef vec_t vec
        _conv_vec(&vec, other, scalar=False)
        if self.val.x < vec.x:
            self.val.x = vec.x

        if self.val.y < vec.y:
            self.val.y = vec.y

        if self.val.z < vec.z:
            self.val.z = vec.z

    def min(self, other):
        """Set this vector's values to be the minimum of the two vectors."""
        cdef vec_t vec
        _conv_vec(&vec, other, scalar=False)
        if self.val.x > vec.x:
            self.val.x = vec.x

        if self.val.y > vec.y:
            self.val.y = vec.y

        if self.val.z > vec.z:
            self.val.z = vec.z

    def __round__(self, object n=0):
        """Performing round() on a Vec rounds each axis."""
        cdef Vec vec = Vec.__new__(Vec)

        vec.val.x = round(self.val.x, n)
        vec.val.y = round(self.val.y, n)
        vec.val.z = round(self.val.z, n)

        return vec

    cdef inline double _mag_sq(self):
        return self.val.x**2 + self.val.y**2 + self.val.z**2

    cdef inline double _mag(self):
        return math.sqrt(self.val.x**2 + self.val.y**2 + self.val.z**2)

    def mag_sq(self):
        """Compute the distance from the vector and the origin."""
        return self._mag_sq()

    def len_sq(self):
        """Compute the distance from the vector and the origin."""
        return self._mag_sq()

    def mag(self):
        """Compute the distance from the vector and the origin."""
        return self._mag()

    def len(self):
        """Compute the distance from the vector and the origin."""
        return self._mag()

    def norm(self):
        """Normalise the Vector.

         This is done by transforming it to have a magnitude of 1 but the same
         direction.
         The vector is left unchanged if it is equal to (0,0,0).
         """
        cdef Vec vec = Vec.__new__(Vec)
        cdef double mag = self._mag()

        if mag == 0:
            # Vec(0, 0, 0).norm = Vec(0, 0, 0), as a special case.
            vec.val.x = vec.val.y = vec.val.z = 0
        else:
            # Disable ZeroDivisionError check, we just checked that.
            with cython.cdivision(True):
                vec.val.x = self.val.x / mag
                vec.val.y = self.val.y / mag
                vec.val.z = self.val.z / mag
        return vec

    def join(self, delim: str=', ') -> str:
        """Return a string with all numbers joined by the passed delimiter.

        This strips off the .0 if no decimal portion exists.
        """
        # :g strips the .0 off of floats if it's an integer.
        return f'{self.val.x:g}{delim}{self.val.y:g}{delim}{self.val.z:g}'

    def __str__(self):
        """Return the values, separated by spaces.

        This is the main format in Valve's file formats.
        This strips off the .0 if no decimal portion exists.
        """
        return f"{self.val.x:g} {self.val.y:g} {self.val.z:g}"

    def __repr__(self):
        """Code required to reproduce this vector."""
        return f"Vec({self.val.x:g}, {self.val.y:g}, {self.val.z:g})"

    def __iter__(self):
        return VecIter.__new__(VecIter, self)

    def __getitem__(self, ind: 'Union[str, int]') -> float:
        """Allow reading values by index instead of name if desired.

        This accepts either 0,1,2 or 'x','y','z' to read values.
        Useful in conjunction with a loop to apply commands to all values.
        """
        cdef unsigned char ind_i
        cdef Py_UCS4 ind_chr
        if isinstance(ind, int):
            try:
                ind_i = ind
            except (TypeError, ValueError, OverflowError):
                pass
            else:
                if ind_i == 0:
                    return self.val.x
                elif ind_i == 1:
                    return self.val.y
                elif ind_i == 2:
                    return self.val.z
        elif isinstance(ind, str) and len(<str>ind) == 1:
            ind_chr = (<str>ind)[0]
            if ind_chr == "x":
                return self.val.x
            elif ind_chr == "y":
                return self.val.y
            elif ind_chr == "z":
                return self.val.z

        raise KeyError(f'Invalid axis: {ind!r}')

    def __setitem__(self, ind: 'Union[str, int]', double val: float) -> None:
        """Allow editing values by index instead of name if desired.

        This accepts either 0,1,2 or 'x','y','z' to edit values.
        Useful in conjunction with a loop to apply commands to all values.
        """
        cdef unsigned char ind_i
        cdef Py_UCS4 ind_chr

        if isinstance(ind, int):
            try:
                ind_i = ind
            except (TypeError, ValueError, OverflowError):
                pass
            else:
                if ind_i == 0:
                    self.val.x = val
                    return
                elif ind_i == 1:
                    self.val.y = val
                    return
                elif ind_i == 2:
                    self.val.z = val
                    return
        elif isinstance(ind, str) and len(<str>ind) == 1:
            ind_chr = (<str>ind)[0]
            if ind_chr == "x":
                self.val.x = val
                return
            elif ind_chr == "y":
                self.val.y = val
                return
            elif ind_chr == "z":
                self.val.z = val
                return

        raise KeyError(f'Invalid axis: {ind!r}')


