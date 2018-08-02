module libsupermesh_c_interface
  use iso_c_binding
  use libsupermesh_tri_intersection

  implicit none

  integer, bind(C) :: tri_buf_size_c = tri_buf_size

  contains

  subroutine intersect_tris_c(tri_A, tri_B, tris_C, n_tris_C) bind(c)
    real(kind = c_double), dimension(2,3), intent(in) :: tri_A, tri_B
    real(kind = c_double), dimension(2, 3, tri_buf_size), intent(out) :: tris_c
    integer, intent(out) :: n_tris_c

    call intersect_tris(tri_A, tri_B, tris_C, n_tris_C)

  end subroutine intersect_tris_c

end module libsupermesh_c_interface
