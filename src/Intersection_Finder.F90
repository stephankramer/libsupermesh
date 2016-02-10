#include "libsupermesh_debug.h"

module libsupermesh_intersection_finder

  use iso_c_binding, only : c_double, c_int
  
  use libsupermesh_debug, only : abort_pinpoint, current_debug_level, &
    & debug_unit
  use libsupermesh_fields, only : eelist_type, mesh_eelist, sloc, deallocate
  use libsupermesh_intersections, only : intersections, deallocate, &
    & intersections_to_csr_sparsity
  use libsupermesh_octtree_intersection_finder, only : octtree_node, &
    & deallocate, octtree_intersection_finder, build_octtree, query_octtree
  use libsupermesh_quadtree_intersection_finder, only : quadtree_node, &
    & deallocate, quadtree_intersection_finder, build_quadtree, query_quadtree

  implicit none

  private

  interface crtree_intersection_finder_set_input
    subroutine libsupermesh_cintersection_finder_set_input(positions, enlist, dim, loc, nnodes, nelements) bind(c)
      use iso_c_binding, only : c_double, c_int
      implicit none
      integer(kind = c_int), intent(in) :: dim, loc, nnodes, nelements
      real(kind = c_double), intent(in), dimension(dim, nnodes) :: positions
      integer(kind = c_int), intent(in), dimension(loc, nelements) :: enlist
    end subroutine libsupermesh_cintersection_finder_set_input
  end interface crtree_intersection_finder_set_input

  interface crtree_intersection_finder_find
    subroutine libsupermesh_cintersection_finder_find(positions, dim, loc) bind(c)
      use iso_c_binding, only : c_double, c_int
      implicit none
      integer(kind = c_int), intent(in) :: dim, loc
      real(kind = c_double), dimension(dim, loc) :: positions
    end subroutine libsupermesh_cintersection_finder_find
  end interface crtree_intersection_finder_find

  interface rtree_intersection_finder_query_output
    subroutine libsupermesh_cintersection_finder_query_output(nelements) bind(c)
      use iso_c_binding, only : c_int
      implicit none
      integer(kind = c_int), intent(out) :: nelements
    end subroutine libsupermesh_cintersection_finder_query_output
  end interface rtree_intersection_finder_query_output

  interface rtree_intersection_finder_get_output
    subroutine libsupermesh_cintersection_finder_get_output(ele, i) bind(c)
      use iso_c_binding, only : c_int
      implicit none
      integer(kind = c_int), intent(out) :: ele
      integer(kind = c_int), intent(in) :: i
    end subroutine libsupermesh_cintersection_finder_get_output
  end interface rtree_intersection_finder_get_output

  interface rtree_intersection_finder_reset
    subroutine libsupermesh_cintersection_finder_reset() bind(c)
      implicit none
    end subroutine libsupermesh_cintersection_finder_reset
  end interface rtree_intersection_finder_reset

  public :: intersections, deallocate, connected, intersection_finder, &
    & advancing_front_intersection_finder, rtree_intersection_finder, &
    & quadtree_intersection_finder, octtree_intersection_finder, &
    & tree_intersection_finder, sort_intersection_finder, &
    & brute_force_intersection_finder
  public :: rtree_intersection_finder_set_input, &
    & rtree_intersection_finder_find, rtree_intersection_finder_query_output, &
    & rtree_intersection_finder_get_output, rtree_intersection_finder_reset
  public :: tree_intersection_finder_set_input, &
    & tree_intersection_finder_find, tree_intersection_finder_query_output, &
    & tree_intersection_finder_get_output, tree_intersection_finder_reset

  interface intersection_finder
    module procedure intersection_finder_intersections, &
      & intersection_finder_csr_sparsity, intersection_finder_lists
  end interface intersection_finder

  interface advancing_front_intersection_finder
    module procedure advancing_front_intersection_finder_intersections, &
      & advancing_front_intersection_finder_csr_sparsity
  end interface advancing_front_intersection_finder

  interface rtree_intersection_finder
    module procedure rtree_intersection_finder_intersections, &
      & rtree_intersection_finder_csr_sparsity
  end interface rtree_intersection_finder

  interface tree_intersection_finder
    module procedure tree_intersection_finder_intersections, &
      & tree_intersection_finder_csr_sparsity
  end interface tree_intersection_finder
  
  interface sort_intersection_finder
    module procedure sort_intersection_finder_rank_1_intersections, &
      & sort_intersection_finder_rank_2_intersections, &
      & sort_intersection_finder_rank_1_csr_sparsity, &
      & sort_intersection_finder_rank_2_csr_sparsity
  end interface sort_intersection_finder

  interface brute_force_intersection_finder
    module procedure brute_force_intersection_finder_intersections, &
      & brute_force_intersection_finder_csr_sparsity
  end interface brute_force_intersection_finder
  
  integer, save :: tree_dim = 0, tree_nelements = 0, tree_neles = 0
  integer, dimension(:), allocatable, save :: tree_eles
  logical, dimension(:), allocatable, save :: tree_seen_ele
  type(octtree_node), save :: tree_octtree
  type(quadtree_node), save :: tree_quadtree

contains

  pure function bbox(coords)
    ! dim x loc
    real, dimension(:, :), intent(in) :: coords

    real, dimension(2, size(coords, 1)) :: bbox

    integer :: i, j

    bbox(1, :) = coords(:, 1)
    bbox(2, :) = coords(:, 1)
    do i = 2, size(coords, 2)
      do j = 1, size(coords, 1)
        bbox(1, j) = min(bbox(1, j), coords(j, i))
        bbox(2, j) = max(bbox(2, j), coords(j, i))
      end do
    end do

  end function bbox

  function connected(positions, enlist, eelist)
    ! dim x nnodes
    real, dimension(:, :), intent(in) :: positions
    ! loc x nelements
    integer, dimension(:, :), intent(in) :: enlist
    type(eelist_type), target, optional, intent(in) :: eelist

    logical :: connected

    integer :: dim, loc, nelements, nnodes

    integer :: ele, i, neigh, nnext, nseen
    integer, dimension(:), allocatable :: next
    logical, dimension(:), allocatable :: seen
    type(eelist_type), pointer :: leelist

    dim = size(positions, 1)
    nnodes = size(positions, 2)
    loc = size(enlist, 1)
    nelements = size(enlist, 2)
    if(nelements == 0) then
      connected = .true.
      return
    end if

    if(present(eelist)) then
      leelist => eelist
    else
      allocate(leelist)
      call mesh_eelist(nnodes, enlist, sloc(dim, loc), leelist)
    end if
    allocate(next(nelements), seen(nelements))
    next(1) = 1
    nnext = 1
    seen(1) = .true.
    seen(2:) = .false.
    nseen = 1
    do while(nnext > 0)
      ele = next(nnext)
      nnext = nnext - 1
      do i = 1, leelist%n(ele)
        neigh = leelist%v(i, ele)
        if(.not. seen(neigh)) then
          nnext = nnext + 1
          next(nnext) = neigh
          seen(neigh) = .true.
          nseen = nseen + 1
        end if
      end do
    end do

    if(.not. present(eelist)) then
      call deallocate(leelist)
      deallocate(leelist)
    end if
    deallocate(next, seen)

    connected = (nseen == nelements)

  end function connected

  subroutine intersection_finder_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab
    
    select case(size(positions_a, 1))
      case(1)
        call sort_intersection_finder(positions_a(1, :), enlist_a, positions_b(1, :), enlist_b, map_ab)
      case(2:3)
        call rtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
      case default
        libsupermesh_abort("Invalid dimension")
    end select
  
  end subroutine intersection_finder_intersections
  
  subroutine intersection_finder_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr

    select case(size(positions_a, 1))
      case(1)
        call sort_intersection_finder(positions_a(1, :), enlist_a, positions_b(1, :), enlist_b, map_ab_indices, map_ab_indptr)
      case(2:3)
        call rtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
      case default
        libsupermesh_abort("Invalid dimension")
    end select
  
  end subroutine intersection_finder_csr_sparsity

  subroutine intersection_finder_lists(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    use libsupermesh_linked_lists, only : ilist, insert
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(ilist), dimension(:), intent(out) :: map_ab
    
    integer :: ele_a, i, nelements_a
    type(intersections), dimension(:), allocatable :: lmap_ab
    
    nelements_a = size(enlist_a, 2)
    allocate(lmap_ab(nelements_a))    
    select case(size(positions_a, 1))
      case(1)
        call sort_intersection_finder(positions_a(1, :), enlist_a, positions_b(1, :), enlist_b, lmap_ab)
      case(2:3)
        call rtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, lmap_ab)
      case default
        libsupermesh_abort("Invalid dimension")
    end select
    do ele_a = 1, nelements_a
      do i = 1, lmap_ab(ele_a)%n
        call insert(map_ab(ele_a), lmap_ab(ele_a)%v(i))
      end do
    end do
    call deallocate(lmap_ab)
    deallocate(lmap_ab)
  
  end subroutine intersection_finder_lists

  ! Advancing front intersection finder, as described in P. E. Farrell and
  ! J. R. Maddison, "Conservative interpolation between volume meshes by local
  ! Galerkin projection", Computer Methods in Applied Mechanics and Engineering,
  ! 200, pp. 89--100, 2011
  subroutine advancing_front_intersection_finder_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab

    integer :: i, j
    integer :: dim, nnodes_b, nnodes_a, nelements_b, nelements_a

    real, dimension(2, size(positions_a, 1)) :: bbox_a
    real, dimension(:, :, :), allocatable :: bboxes_b
    type(eelist_type) :: eelist_b, eelist_a

    integer :: clue_a, ele_b, ele_a, loc_b, loc_a, neigh_b, neigh_a, nsub_a, seed_a
    integer, dimension(:), allocatable :: front_b, ints
    logical, dimension(:), allocatable :: seen_b, seen_a
    integer, dimension(:, :), allocatable :: front_a
    integer :: nfront_b, nfront_a, nints

!     real :: t_0

    dim = size(positions_b, 1)
    nnodes_b = size(positions_b, 2)
    nnodes_a = size(positions_a, 2)
    loc_b = size(enlist_b, 1)
    nelements_b = size(enlist_b, 2)
    loc_a = size(enlist_a, 1)
    nelements_a = size(enlist_a, 2)
    if(nelements_b == 0 .or. nelements_a == 0) then
      do ele_a = 1, nelements_a
        allocate(map_ab(ele_a)%v(0))
        map_ab(ele_a)%n = 0
      end do
      return
    end if

!     t_0 = mpi_wtime()
    call mesh_eelist(nnodes_b, enlist_b, sloc(dim, loc_b), eelist_b)
    call mesh_eelist(nnodes_a, enlist_a, sloc(dim, loc_a), eelist_a)
!     ewrite(2, "(a,e25.17e3)") "eelist creation time = ", mpi_wtime() - t_0
    allocate(bboxes_b(2, dim, nelements_b))
    do i = 1, nelements_b
      bboxes_b(:, :, i) = bbox(positions_b(:, enlist_b(:, i)))
    end do

    allocate(seen_b(nelements_b), seen_a(nelements_a), front_b(nelements_b), &
      & front_a(2, nelements_a), ints(nelements_b))
    seen_b = .false.
    seen_a = .false.
    ! Stage 0: Initial target mesh seed element
    seed_a = 1
    nsub_a = 0
    seed_a_loop: do
      nsub_a = nsub_a + 1
      seen_a(seed_a) = .true.
      bbox_a = bbox(positions_a(:, enlist_a(:, seed_a)))

      ! Stage 1a: Find intersections with the target mesh seed element via a
      ! brute force search
      nints = 0
      do ele_b = 1, nelements_b
        if(bboxes_intersect(bbox_a, bboxes_b(:, :, ele_b))) then
          nints = nints + 1
          ints(nints) = ele_b
        end if
      end do
      allocate(map_ab(seed_a)%v(nints))
      map_ab(seed_a)%v = ints(:nints)
      map_ab(seed_a)%n = nints

      ! Stage 1b: Advance the target mesh front
      nfront_a = 0
      do i = 1, eelist_a%n(seed_a)
        neigh_a = eelist_a%v(i, seed_a)
        if(.not. seen_a(neigh_a)) then
          nfront_a = nfront_a + 1
          front_a(1, nfront_a) = neigh_a
          front_a(2, nfront_a) = seed_a
          seen_a(neigh_a) = .true.
        end if
      end do

      do while(nfront_a > 0)
        ele_a = front_a(1, nfront_a)
        clue_a = front_a(2, nfront_a)
        nfront_a = nfront_a - 1
        bbox_a = bbox(positions_a(:, enlist_a(:, ele_a)))

        ! Stage 2a: Initialise the donor mesh front
        nfront_b = map_ab(clue_a)%n
        front_b(:nfront_b) = map_ab(clue_a)%v
        seen_b(front_b(:nfront_b)) = .true.

        ! Stage 2b: Find intersections with the target mesh element by
        ! advancing the donor mesh front
        nints = 0
        i = 1
        do while(i <= nfront_b)
          ele_b = front_b(i)
          if(bboxes_intersect(bbox_a, bboxes_b(:, :, ele_b))) then
            ! An intersection has been found
            nints = nints + 1
            ints(nints) = ele_b
            ! Advance the donor mesh front
            do j = 1, eelist_b%n(ele_b)
              neigh_b = eelist_b%v(j, ele_b)
              if(.not. seen_b(neigh_b)) then
                nfront_b = nfront_b + 1
                front_b(nfront_b) = neigh_b
                seen_b(neigh_b) = .true.
              end if
            end do
          end if
          i = i + 1
        end do
        do i = 1, nfront_b
          seen_b(front_b(i)) = .false.
        end do
!         if(nints == 0) then
!           ewrite(-1, "(a,i0)") "WARNING: Failed to find intersections for target element ", ele_a
!         end if
        allocate(map_ab(ele_a)%v(nints))
        map_ab(ele_a)%v = ints(:nints)
        map_ab(ele_a)%n = nints

        ! Stage 2c: Advance the target mesh front
        do i = 1, eelist_a%n(ele_a)
          neigh_a = eelist_a%v(i, ele_a)
          if(.not. seen_a(neigh_a)) then
            nfront_a = nfront_a + 1
            front_a(1, nfront_a) = neigh_a
            front_a(2, nfront_a) = ele_a
            seen_a(neigh_a) = .true.
          end if
        end do
      end do

      ! Stage 3: Find a new target mesh seed
      do while(seen_a(seed_a))
        seed_a = seed_a + 1
        if(seed_a > nelements_a) exit seed_a_loop
      end do
      if(nsub_a == 1) then
        ewrite(-1, "(a)") "WARNING: Target mesh is not connected"
      end if
    end do seed_a_loop
    if(nsub_a > 1) then
      ewrite(-1 ,"(a,i0)") "WARNING: Number of target connected sub-domains = ", nsub_a
    end if

    deallocate(seen_b, seen_a, front_b, front_a, ints)
    call deallocate(eelist_b)
    call deallocate(eelist_a)
    deallocate(bboxes_b)
  
  contains

    pure function bboxes_intersect(bbox_1, bbox_2) result(intersect)
      ! 2 x dim
      real, dimension(:, :), intent(in) :: bbox_1
      ! 2 x dim
      real, dimension(:, :), intent(in) :: bbox_2

      logical :: intersect

      integer :: i

      do i = 1, size(bbox_1, 2)
        ! Strict inequalities required here for the advancing front intersection
        ! finder to work with axis aligned elements
        if(bbox_2(2, i) < bbox_1(1, i) .or. bbox_2(1, i) > bbox_1(2, i)) then
          intersect = .false.
          return
        end if
      end do
      intersect = .true.

    end function bboxes_intersect

  end subroutine advancing_front_intersection_finder_intersections

  subroutine advancing_front_intersection_finder_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr

    type(intersections), dimension(:), allocatable :: map_ab

    allocate(map_ab(size(enlist_a, 2)))
    call advancing_front_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    call intersections_to_csr_sparsity(map_ab, map_ab_indices, map_ab_indptr)
    call deallocate(map_ab)
    deallocate(map_ab)

  end subroutine advancing_front_intersection_finder_csr_sparsity

  subroutine rtree_intersection_finder_set_input(positions, enlist)
    ! dim x nnodes_b
    real(kind = c_double), dimension(:, :), intent(in) :: positions
    ! loc x nelements_b
    integer(kind = c_int), dimension(:, :), intent(in) :: enlist

    integer(kind = c_int) :: loc, dim, nelements, nnodes

    dim = size(positions, 1)
    if(.not. any(dim == (/2, 3/))) then
      libsupermesh_abort("Invalid dimension")
    end if
    nnodes = size(positions, 2)
    loc = size(enlist, 1)
    nelements = size(enlist, 2)

    call crtree_intersection_finder_set_input(positions, enlist, dim, loc, nnodes, nelements)

  end subroutine rtree_intersection_finder_set_input

  subroutine rtree_intersection_finder_find(positions)
    ! dim x loc
    real(kind = c_double), dimension(:, :), intent(in) :: positions

    integer(kind = c_int) :: loc, dim

    dim = size(positions, 1)
    loc = size(positions, 2)

    call crtree_intersection_finder_find(positions, dim, loc)

  end subroutine rtree_intersection_finder_find

  subroutine rtree_intersection_finder_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab

    integer :: ele_a, ele_b, i, nelements_a, nints

    nelements_a = size(enlist_a, 2)

    call rtree_intersection_finder_set_input(positions_b, enlist_b)
    do ele_a = 1, nelements_a
      call rtree_intersection_finder_find(positions_a(:, enlist_a(:, ele_a)))
      call rtree_intersection_finder_query_output(nints)
      map_ab(ele_a)%n = nints
      allocate(map_ab(ele_a)%v(nints))
      do i = 1, nints
        call rtree_intersection_finder_get_output(ele_b, i)
        map_ab(ele_a)%v(i) = ele_b
      end do
    end do
    call rtree_intersection_finder_reset()

  end subroutine rtree_intersection_finder_intersections

  subroutine rtree_intersection_finder_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr

    type(intersections), dimension(:), allocatable :: map_ab

    allocate(map_ab(size(enlist_a, 2)))
    call rtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    call intersections_to_csr_sparsity(map_ab, map_ab_indices, map_ab_indptr)
    call deallocate(map_ab)
    deallocate(map_ab)

  end subroutine rtree_intersection_finder_csr_sparsity

  subroutine tree_intersection_finder_set_input(positions, enlist)
    ! dim x nnodes
    real, dimension(:, :), intent(in) :: positions
    ! loc x nelements
    integer, dimension(:, :), intent(in) :: enlist
    
    call tree_intersection_finder_reset()
    
    tree_dim = size(positions, 1)
    tree_nelements = size(enlist, 2)       
    select case(tree_dim)
      case(2)
        tree_quadtree = build_quadtree(positions, enlist)
      case(3)
        tree_octtree = build_octtree(positions, enlist)
      case default
        libsupermesh_abort("Invalid dimension")
    end select
    allocate(tree_eles(tree_nelements), tree_seen_ele(tree_nelements))
    tree_neles = 0 
    tree_seen_ele = .false.
    
  end subroutine tree_intersection_finder_set_input

  subroutine tree_intersection_finder_find(positions)
    ! dim x loc
    real, dimension(:, :), intent(in) :: positions
    
    integer :: i
    real, dimension(2, tree_dim) :: bbox
    
    bbox(1, :) = positions(:, 1)
    bbox(2, :) = positions(:, 1)
    do i = 1, tree_dim
      bbox(1, i) = min(bbox(1, i), minval(positions(i, :)))
      bbox(2, i) = max(bbox(1, i), maxval(positions(i, :)))
    end do
    tree_seen_ele(tree_eles(:tree_neles)) = .false.
    tree_neles = 0
    select case(tree_dim)
      case(2)
        call query_quadtree(tree_quadtree, bbox, tree_eles, tree_neles, tree_seen_ele)
      case(3)
        call query_octtree(tree_octtree, bbox, tree_eles, tree_neles, tree_seen_ele)
      case default
        libsupermesh_abort("Invalid dimension")
    end select
    
  end subroutine tree_intersection_finder_find
  
  subroutine tree_intersection_finder_query_output(nelements)
    integer, intent(out) :: nelements
    
    nelements = tree_neles
  
  end subroutine tree_intersection_finder_query_output
  
  subroutine tree_intersection_finder_get_output(ele, i)
    integer, intent(out) :: ele
    integer, intent(in) :: i
        
    ele = tree_eles(i)
      
  end subroutine tree_intersection_finder_get_output
  
  subroutine tree_intersection_finder_reset()    
    if(tree_dim == 0) return
  
    select case(tree_dim)
      case(2)
        call deallocate(tree_quadtree)
      case(3)
        call deallocate(tree_octtree)
      case default
        libsupermesh_abort("Invalid dimension")
    end select
    tree_dim = 0
    tree_nelements = 0  
    deallocate(tree_eles, tree_seen_ele)
    tree_neles = 0
  
  end subroutine tree_intersection_finder_reset

  subroutine tree_intersection_finder_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab

    select case(size(positions_a, 1))
      case(2)
        call quadtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
      case(3)
        call octtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
      case default
        libsupermesh_abort("Invalid dimension")
    end select

  end subroutine tree_intersection_finder_intersections

  subroutine tree_intersection_finder_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr

    select case(size(positions_a, 1))
      case(2)
        call quadtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
      case(3)
        call octtree_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
      case default
        libsupermesh_abort("Invalid dimension")
    end select

  end subroutine tree_intersection_finder_csr_sparsity
  
  pure subroutine sort_intersection_finder_rank_1_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! nnodes_a
    real, dimension(:), intent(in) :: positions_a
    ! 2 x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! nnodes_b
    real, dimension(:), intent(in) :: positions_b
    ! 2 x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab
    
    integer :: ele_a, ele_b, i, j, nelements_a, nelements_b, nints
    integer, dimension(:), allocatable :: indices_a, indices_b, ints, work
    real, dimension(2) :: interval_a, interval_b
    real, dimension(:), allocatable :: left_positions_a, left_positions_b
    
    nelements_a = size(enlist_a, 2)
    nelements_b = size(enlist_b, 2)
    
    allocate(left_positions_a(nelements_a), left_positions_b(nelements_b))
    do ele_a = 1, nelements_a
      left_positions_a(ele_a) = minval(positions_a(enlist_a(:, ele_a)))
    end do
    do ele_b = 1, nelements_b
      left_positions_b(ele_b) = minval(positions_b(enlist_b(:, ele_b)))
    end do
    
    allocate(indices_a(nelements_a), indices_b(nelements_b), work(max(nelements_a, nelements_b)))
    call merge_sort(left_positions_a, indices_a, work(:nelements_a))
    call merge_sort(left_positions_b, indices_b, work(:nelements_b))
    deallocate(left_positions_a, left_positions_b, work)
    
    allocate(ints(nelements_b))
    j = 1
    do i = 1, nelements_a
      ele_a = indices_a(i)
      interval_a = positions_a(enlist_a(:, ele_a))
      nints = 0
      do while(j <= nelements_b)
        ele_b = indices_b(j)
        interval_b = positions_b(enlist_b(:, ele_b))
        if(maxval(interval_b) <= minval(interval_a)) then
          j = j + 1
        else if(minval(interval_b) >= maxval(interval_a)) then
          exit
        else
          nints = nints + 1
          ints(nints) = ele_b
          j = j + 1
        end if
      end do
      if(nints > 0) j = j - 1
      allocate(map_ab(ele_a)%v(nints))
      map_ab(ele_a)%v = ints(:nints)
      map_ab(ele_a)%n = nints
    end do
    
    deallocate(indices_a, indices_b, ints)
  
  contains
  
    ! A very basic merge sort implementation
    pure recursive subroutine merge_sort(v, indices, work)
      real, dimension(:), intent(in) :: v
      integer, dimension(:), intent(inout) :: indices
      integer, dimension(:), intent(out) :: work
      
      integer :: i, i_1, i_2, j, n 
      
      n = size(v, 1)
      
      if(n <= 4) then
        ! Switch to a basic quadratic sort for small inputs
        do i = 1, n
          indices(i) = i
          do j = i + 1, n
            ! < here for a stable sort
            if(v(j) < v(indices(i))) indices(i) = j
          end do
        end do
      else
        ! Otherwise split, recurse, and merge
        call merge_sort(v(1:n / 2), indices(1:n / 2), work(1:n / 2))
        call merge_sort(v((n / 2) + 1:n), indices((n / 2) + 1:n), work((n / 2) + 1:n))
        work(1:n / 2) = indices(1:n / 2)
        work((n / 2) + 1:n) = indices((n / 2) + 1:n) + (n / 2)
        i_1 = 1
        i_2 = (n / 2) + 1
        do i = 1, n
          if(i_1 > (n / 2)) then
            indices(i:) = work(i_2:)
            exit
          else if(i_2 > n) then
            indices(i:) = work(i_1:n / 2)
            exit
          ! <= here for a stable sort
          else if(v(work(i_1)) <= v(work(i_2))) then
            indices(i) = work(i_1)
            i_1 = i_1 + 1
          else
            indices(i) = work(i_2)
            i_2 = i_2 + 1
          end if
        end do
      end if
      
    end subroutine merge_sort
    
  end subroutine sort_intersection_finder_rank_1_intersections
  
  pure subroutine sort_intersection_finder_rank_2_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! 1 x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! 2 x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! 1 x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! 2 x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab
    
    call sort_intersection_finder(positions_a(1, :), enlist_a, positions_b(1, :), enlist_b, map_ab)
  
  end subroutine sort_intersection_finder_rank_2_intersections

  pure subroutine sort_intersection_finder_rank_1_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! nnodes_a
    real, dimension(:), intent(in) :: positions_a
    ! 2 x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! nnodes_b
    real, dimension(:), intent(in) :: positions_b
    ! 2 x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr
    
    type(intersections), dimension(:), allocatable :: map_ab

    allocate(map_ab(size(enlist_a, 2)))
    call sort_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    call intersections_to_csr_sparsity(map_ab, map_ab_indices, map_ab_indptr)
    call deallocate(map_ab)
    deallocate(map_ab)
  
  end subroutine sort_intersection_finder_rank_1_csr_sparsity

  pure subroutine sort_intersection_finder_rank_2_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! 1 x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! 2 x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! 1 x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! 2 x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr
    
    type(intersections), dimension(:), allocatable :: map_ab

    allocate(map_ab(size(enlist_a, 2)))
    call sort_intersection_finder(positions_a(1, :), enlist_a, positions_b(1, :), enlist_b, map_ab)
    call intersections_to_csr_sparsity(map_ab, map_ab_indices, map_ab_indptr)
    call deallocate(map_ab)
    deallocate(map_ab)
  
  end subroutine sort_intersection_finder_rank_2_csr_sparsity

  ! Brute force intersection finder.
  pure subroutine brute_force_intersection_finder_intersections(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! nelements_a
    type(intersections), dimension(:), intent(out) :: map_ab

    integer :: ele_a, ele_b, nelements_a, nelements_b
    real, dimension(2, size(positions_a, 1)) :: bbox_a, bbox_b

    integer, dimension(:), allocatable :: ints
    integer :: nints

    nelements_a = size(enlist_a, 2)
    nelements_b = size(enlist_b, 2)

    allocate(ints(nelements_b))
    do ele_a = 1, nelements_a
      bbox_a = bbox(positions_a(:, enlist_a(:, ele_a)))
      nints = 0
      do ele_b = 1, nelements_b
        bbox_b = bbox(positions_b(:, enlist_b(:, ele_b)))
        if(bboxes_intersect(bbox_a, bbox_b)) then
          nints = nints + 1
          ints(nints) = ele_b
        end if
      end do

      map_ab(ele_a)%n = nints
      allocate(map_ab(ele_a)%v(nints))
      map_ab(ele_a)%v = ints(:nints)
    end do
    deallocate(ints)
    
  contains

    pure function bboxes_intersect(bbox_1, bbox_2) result(intersect)
      ! 2 x dim
      real, dimension(:, :), intent(in) :: bbox_1
      ! 2 x dim
      real, dimension(:, :), intent(in) :: bbox_2

      logical :: intersect

      integer :: i

      do i = 1, size(bbox_1, 2)
        if(bbox_2(2, i) <= bbox_1(1, i) .or. bbox_2(1, i) >= bbox_1(2, i)) then
          intersect = .false.
          return
        end if
      end do
      intersect = .true.

    end function bboxes_intersect

  end subroutine brute_force_intersection_finder_intersections

  pure subroutine brute_force_intersection_finder_csr_sparsity(positions_a, enlist_a, positions_b, enlist_b, map_ab_indices, map_ab_indptr)
    ! dim x nnodes_a
    real, dimension(:, :), intent(in) :: positions_a
    ! loc_a x nelements_a
    integer, dimension(:, :), intent(in) :: enlist_a
    ! dim x nnodes_b
    real, dimension(:, :), intent(in) :: positions_b
    ! loc_b x nelements_b
    integer, dimension(:, :), intent(in) :: enlist_b
    ! Compressed Sparse Row (CSR) sparsity pattern, as described in:
    !   http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.sparse.csr_matrix.html
    integer, dimension(:), allocatable, intent(out) :: map_ab_indices
    ! nelements_a + 1
    integer, dimension(:), intent(out) :: map_ab_indptr

    type(intersections), dimension(:), allocatable :: map_ab

    allocate(map_ab(size(enlist_a, 2)))
    call brute_force_intersection_finder(positions_a, enlist_a, positions_b, enlist_b, map_ab)
    call intersections_to_csr_sparsity(map_ab, map_ab_indices, map_ab_indptr)
    call deallocate(map_ab)
    deallocate(map_ab)

  end subroutine brute_force_intersection_finder_csr_sparsity

end module libsupermesh_intersection_finder