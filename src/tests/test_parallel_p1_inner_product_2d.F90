#include "libsupermesh_debug.h"

subroutine test_parallel_p1_inner_product_2d() bind(c)

  use iso_c_binding, only : c_int8_t
  use iso_fortran_env, only : error_unit, output_unit

  use libsupermesh_debug, only : abort_pinpoint
  use libsupermesh_halo_ownership, only : element_ownership
  use libsupermesh_parallel_supermesh, only : parallel_supermesh
  use libsupermesh_read_halos, only : halo_type, deallocate, read_halo
  use libsupermesh_read_triangle, only : read_ele, read_node
  use libsupermesh_supermesh, only : triangle_area
  use libsupermesh_unittest_tools, only : operator(.fne.), report_test

  implicit none

#include <mpif.h>
  
  ! Input Triangle mesh base names
  character(len = *), parameter :: basename_a = "data/triangle_0_01", &
                                 & basename_b = "data/square_0_01"
  real, parameter :: area_ref = 0.5D0, integral_ref = 8.3333333333333398D-02

  character(len = int(log10(real(huge(0)))) + 1) :: rank_chr, nprocs_chr
  integer :: ierr, integer_extent, nprocs, rank, real_extent
 
  integer :: nelements_a, nelements_b, nnodes_a, nnodes_b
  integer, dimension(:), allocatable :: ele_owner_a, ele_owner_b
  integer, dimension(:, :), allocatable :: enlist_a, enlist_b
  real, dimension(:), allocatable :: field_a
  real, dimension(:), allocatable, target :: field_b
  real, dimension(:, :), allocatable :: positions_a, positions_b
  type(halo_type) :: halo_a, halo_b
  
  integer :: data_nnodes_b
  real, dimension(:), allocatable, target :: data_field_b
  
  ! Quadrature rule from D. A. Dunavant, "High degree efficient symmetrical
  ! Gaussian quadrature rules for the triangle", International Journal for
  ! Numerical Methods in Engineering, 21, pp. 1129--1148, 1985, appendix II
  real, dimension(3), parameter :: quad_weights = (/1.0D0, 1.0D0, 1.0D0/) / 3.0D0
  real, dimension(3, 3), parameter :: quad_points = reshape((/4.0D0, 1.0D0, 1.0D0, 1.0D0, 4.0D0, 1.0D0, 1.0D0, 1.0D0, 4.0D0/) / 6.0D0, (/3, 3/))
  real :: area_parallel, integral_parallel

  call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr);  assert(ierr == MPI_SUCCESS)
  call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr);  assert(ierr == MPI_SUCCESS)
  write(rank_chr, "(i0)") rank
  write(nprocs_chr, "(i0)") nprocs
  rank_chr = adjustl(rank_chr)
  nprocs_chr = adjustl(nprocs_chr)
  call MPI_Type_extent(MPI_INTEGER, integer_extent, ierr);  assert(ierr == MPI_SUCCESS)
  call MPI_Type_extent(MPI_DOUBLE_PRECISION, real_extent, ierr);  assert(ierr == MPI_SUCCESS)

  ! Read the donor mesh partition
  call read_node(trim(basename_a) // "_" // trim(nprocs_chr) // "_" // trim(rank_chr) // ".node", dim = 2, coords = positions_a)
  call read_ele(trim(basename_a) // "_" // trim(nprocs_chr) // "_" // trim(rank_chr) // ".ele", dim = 2, enlist = enlist_a)
  nnodes_a = size(positions_a, 2)
  nelements_a = size(enlist_a, 2)
  ! Read donor mesh halo data ...
  call read_halo(trim(basename_a) // "_" // trim(nprocs_chr), halo_a, level = 2)
  ! ... and determine the donor mesh element ownership
  allocate(ele_owner_a(nelements_a))
  call element_ownership(nnodes_a, enlist_a, halo_a, ele_owner_a)
  ! Construct a donor P1 field equal to: x
  allocate(field_a(nnodes_a))
  field_a = positions_a(1, :)

  ! Read the target mesh partition
  call read_node(trim(basename_b) // "_" // trim(nprocs_chr) // "_" // trim(rank_chr) // ".node", dim = 2, coords = positions_b)
  call read_ele(trim(basename_b) // "_" // trim(nprocs_chr) // "_" // trim(rank_chr) // ".ele", dim = 2, enlist = enlist_b)
  nnodes_b = size(positions_b, 2)
  nelements_b = size(enlist_b, 2)
  ! Read target mesh halo data ...
  call read_halo(trim(basename_b) // "_" // trim(nprocs_chr), halo_b, level = 2)
  ! ... and determine the target mesh element ownership
  allocate(ele_owner_b(nelements_b))
  call element_ownership(nnodes_b, enlist_b, halo_b, ele_owner_b)
  ! Construct a target P1 field equal to: y
  allocate(field_b(nnodes_b))
  field_b = positions_b(2, :)

  ! Perform multi-mesh integration
  area_parallel = 0.0D0
  integral_parallel = 0.0D0
  call parallel_supermesh(positions_a, enlist_a, ele_owner_a, &
                        & positions_b, enlist_b, ele_owner_b, &
                        & pack_data_b, unpack_data_b, intersection_calculation, &
                        & comm = MPI_COMM_WORLD)
  ! Deallocate any remaining unpacked communicated data
  call cleanup_unpack_data_b()

  ! Sum all process contributions to the multi-mesh integrals
  call MPI_Allreduce(MPI_IN_PLACE, area_parallel, 1, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_WORLD, ierr);  assert(ierr == MPI_SUCCESS)
  call MPI_Allreduce(MPI_IN_PLACE, integral_parallel, 1, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_WORLD, ierr);  assert(ierr == MPI_SUCCESS)

  flush(output_unit)
  flush(error_unit)
  call MPI_Barrier(MPI_COMM_WORLD, ierr);  assert(ierr == MPI_SUCCESS)
  if(rank == 0) then
    ! Display the multi-mesh integrals on rank 0
    print "(a,e26.18e3,a,e26.18e3,a)", "Area     = ", area_parallel, " (error = ", abs(area_parallel - area_ref), ")"
    print "(a,e26.18e3,a,e26.18e3,a)", "Integral = ", integral_parallel, " (error = ", abs(integral_parallel - integral_ref), ")"
    
    ! Test the multi-mesh integrals against the reference values
    call report_test("[test_parallel_p1_inner_product_2d area]", area_parallel .fne. area_ref, .false., "Incorrect area")
    call report_test("[test_parallel_p1_inner_product_2d integral]", integral_parallel .fne. integral_ref, .false., "Incorrect integral")
  end if
  flush(output_unit)
  flush(error_unit)

  ! Cleanup
  deallocate(positions_a, enlist_a, ele_owner_a, field_a, &
           & positions_b, enlist_b, ele_owner_b, field_b)
  call deallocate(halo_a)
  call deallocate(halo_b)

contains

  ! Given the provided mesh vertices and elements, pack data for communication
  subroutine pack_data_b(nodes_b, eles_b, data_b)
    ! Mesh vertices to be communicated
    integer, dimension(:), intent(in) :: nodes_b
    ! Mesh elements to be communicated
    integer, dimension(:), intent(in) :: eles_b
    ! Packed data for communication
    integer(kind = c_int8_t), dimension(:), allocatable, intent(out) :: data_b
    
    integer :: ndata_b, position
    real, dimension(:), allocatable :: data_field_b
    
    ! Gather P1 field values for communication
    allocate(data_field_b(size(nodes_b)))
    data_field_b = field_b(nodes_b)
    
    ! Pack data for communication:
    !   (number of P1 nodes) reals -- communicated P1 field values
    ndata_b = size(data_field_b) * real_extent
    allocate(data_b(ndata_b))
    position = 0
    call MPI_Pack(data_field_b, size(data_field_b), MPI_DOUBLE_PRECISION, data_b, ndata_b, position, MPI_COMM_WORLD, ierr);  assert(ierr == MPI_SUCCESS)
    
    deallocate(data_field_b)
    
  end subroutine pack_data_b
  
  ! Unpack communicated data
  subroutine unpack_data_b(nnodes_b, nelements_b, data_b)
    ! Number of communicated mesh vertices
    integer, intent(in) :: nnodes_b
    ! Number of communicated elements
    integer, intent(in) :: nelements_b
    integer(kind = c_int8_t), dimension(:), intent(in) :: data_b
    
    integer :: position
    
    ! Deallocate any previously unpacked communicated data
    call cleanup_unpack_data_b()
    
    position = 0
    ! Store the number of P1 nodes
    data_nnodes_b = nnodes_b
    ! Unpack the P1 field values
    allocate(data_field_b(data_nnodes_b))
    call MPI_Unpack(data_b, size(data_b), position, data_field_b, data_nnodes_b, MPI_DOUBLE_PRECISION, MPI_COMM_WORLD, ierr);  assert(ierr == MPI_SUCCESS)
    
  end subroutine unpack_data_b
  
  ! Deallocate any previously unpacked communicated data
  subroutine cleanup_unpack_data_b()
    if(allocated(data_field_b)) deallocate(data_field_b)
  end subroutine cleanup_unpack_data_b
  
  ! Evaluate P1 basis functions at a given point
  pure function basis_functions_p1(cell_coords, coord) result(fns)
    ! Triangle vertex coordinates
    ! Shape: dim x loc_p1
    real, dimension(2, 3), intent(in) :: cell_coords
    ! Coordinate at which to evaluate the basis functions
    ! Shape: dim
    real, dimension(2), intent(in) :: coord

    real, dimension(3) :: fns

    real, dimension(2) :: e1, e2
    real, dimension(2, 2) :: jac
        
    e1 = cell_coords(:, 2) - cell_coords(:, 1)
    e2 = cell_coords(:, 3) - cell_coords(:, 1)

    jac(1, 1) =  e2(2);  jac(1, 2) = -e2(1)
    jac(2, 1) = -e1(2);  jac(2, 2) =  e1(1)
    jac = jac / (jac(1, 1) * jac(2, 2) - jac(1, 2) * jac(2, 1))

    fns(2:3) = matmul(jac, coord - cell_coords(:, 1))
    fns(1) = 1.0D0 - fns(2) - fns(3)

  end function basis_functions_p1

  ! Interpolate a P1 function at given point
  pure function interpolate_p1(cell_coords_d, cell_x_d, coord_s) result(x_s)
    ! Triangle vertex coordinates
    ! Shape: dim x loc_p1
    real, dimension(2, 3), intent(in) :: cell_coords_d
    ! P1 nodal values
    ! Shape: loc_p1
    real, dimension(3), intent(in) :: cell_x_d
    ! Coordinate at which to evaluate the P1 function
    ! Shape: dim
    real, dimension(2), intent(in) :: coord_s

    real :: x_s

    x_s = dot_product(basis_functions_p1(cell_coords_d, coord_s), cell_x_d)

  end function interpolate_p1
  
  ! Perform calculations on the local supermesh
  subroutine intersection_calculation(positions_a, positions_b, positions_c, nodes_b, ele_a, ele_b, local)
    ! Target mesh element vertex coordinates
    ! Shape: dim x loc_a
    real, dimension(:, :), intent(in) :: positions_a
    ! Donor mesh element vertex coordinates
    ! Shape: dim x loc_b
    real, dimension(:, :), intent(in) :: positions_b
    ! Supermesh element vertex coordinates
    ! Shape: dim x loc_c x nelements_c
    real, dimension(:, :, :), intent(in) :: positions_c
    ! Donor mesh vertex indices
    ! Shape: loc_b
    integer, dimension(:), intent(in) :: nodes_b
    ! Target mesh element
    integer, intent(in) :: ele_a
    ! Donor mesh element
    integer, intent(in) :: ele_b
    ! Whether this is a local calculation or a calculation using communicated
    ! data
    logical, intent(in) :: local
    
    integer :: ele_c, i
    real :: area
    real, dimension(2) :: quad_point
    real, dimension(:), pointer :: lfield_b
    
    if(local) then
      ! If this is a local calculation, use the local P1 field data
      lfield_b => field_b
    else
      ! Otherwise, use the unpacked communicated P1 field data
      lfield_b => data_field_b
    end if
    
    do ele_c = 1, size(positions_c, 3)
      ! Compute the supermesh triangle area
      area = triangle_area(positions_c(:, :, ele_c))
      ! Local contribution to the intersection area
      area_parallel = area_parallel + area
      ! Local contribution to the multi-mesh inner product, evaluated using
      ! degree 2 quadrature
      do i = 1, size(quad_weights)
        quad_point(1) = dot_product(quad_points(:, i), positions_c(1, :, ele_c))
        quad_point(2) = dot_product(quad_points(:, i), positions_c(2, :, ele_c))
        integral_parallel = integral_parallel + quad_weights(i) * area &
                                              & * interpolate_p1(positions_b, lfield_b(nodes_b), quad_point) &
                                              & * interpolate_p1(positions_a, field_a(enlist_a(:, ele_a)), quad_point)
      end do
    end do
        
  end subroutine intersection_calculation
  
end subroutine test_parallel_p1_inner_product_2d