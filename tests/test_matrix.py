"""Tests the Matrix/FrozenMatrix class in srctools.math."""
import pickle

import copy

from helpers import *


# noinspection PyArgumentList
def test_bad_from_basis(
    py_c_vec: PyCVec,
    frozen_thawed_vec: VecClass,
    frozen_thawed_matrix: MatrixClass,
) -> None:
    """Test invalid arguments to Matrix.from_basis()"""
    Vec = frozen_thawed_vec
    Matrix = frozen_thawed_matrix

    v = Vec(0, 1, 0)
    with pytest.raises(TypeError):
        Matrix.from_basis()
    with pytest.raises(TypeError):
        Matrix.from_basis(x=v)
    with pytest.raises(TypeError):
        Matrix.from_basis(y=v)
    with pytest.raises(TypeError):
        Matrix.from_basis(z=v)


def test_matrix_no_iteration(py_c_vec: PyCVec) -> None:
    """Test that Matrix cannot be iterated, as this is rather useless."""
    Matrix = vec_mod.Matrix
    with pytest.raises(TypeError):
        iter(Matrix())
    with pytest.raises(TypeError):
        list(Matrix())

def test_copy(py_c_vec: PyCVec) -> None:
    """Test copying Matrixes."""
    Matrix = vec_mod.Matrix
    FrozenMatrix = vec_mod.FrozenMatrix

    # Some random rotation, so all points are different.
    test_data = (38, 42, 63)

    orig = Matrix.from_angle(*test_data)

    cpy_meth = orig.copy()

    assert orig is not cpy_meth  # Must be a new object.
    assert cpy_meth is not orig.copy()  # Cannot be cached
    assert type(orig) is type(cpy_meth)
    assert orig == cpy_meth  # Numbers must be exactly identical!

    cpy = copy.copy(orig)

    assert orig is not cpy
    assert cpy_meth is not copy.copy(orig)
    assert orig == cpy

    dcpy = copy.deepcopy(orig)

    assert orig is not dcpy
    assert orig == dcpy

    frozen = FrozenMatrix.from_angle(*test_data)
    # Copying FrozenMatrix does nothing.
    assert frozen is frozen.copy()
    assert frozen is copy.copy(frozen)
    assert frozen is copy.deepcopy(frozen)


def test_pickle(py_c_vec: PyCVec, frozen_thawed_matrix: MatrixClass) -> None:
    """Test pickling and unpickling matrices."""
    Matrix = frozen_thawed_matrix
    test_data = (38, 42, 63)

    orig = Matrix.from_angle(*test_data)

    pick = pickle.dumps(orig)
    thaw = pickle.loads(pick)

    assert orig is not thaw
    assert orig == thaw

    # Ensure we test the right frozen vs mutable class.
    CyMatrix = getattr(vec_mod, 'Cy_' + Matrix.__name__)
    PyMatrix = getattr(vec_mod, 'Py_' + Matrix.__name__)

    # Ensure both produce the same pickle - so they can be interchanged.
    # Copy over the floats, since calculations are going to be slightly different
    # due to optimisation etc. That's tested elsewhere to ensure accuracy, but
    # we need exact binary identity.
    data = [
        orig[x, y]
        for x in (0, 1, 2)
        for y in (0, 1, 2)
    ]
    cy_mat = CyMatrix._from_raw(*data)
    py_mat = PyMatrix._from_raw(*data)

    assert pickle.dumps(cy_mat) == pickle.dumps(py_mat)
