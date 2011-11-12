!!****if* source/Grid/GridMain/paramesh/Grid_markRefineDerefine
!!
!! NAME
!!  Grid_markRefineDerefine
!!
!! SYNOPSIS
!!
!!  Grid_markRefineDerefine()
!!  
!! DESCRIPTION 
!!  Mark blocks for refinement or derefinement
!!  This routine is used with AMR only where individual 
!!  blocks are marked for refinement or derefinement based upon
!!  some refinement criterion. The Uniform Grid does not need
!!  this routine, and uses the stub.
!!
!! ARGUMENTS
!! 
!! NOTES
!!
!! Every unit uses a few unit scope variables that are
!! accessible to all routines within the unit, but not to the
!! routines outside the unit. For Grid unit these variables begin with "gr_"
!! like, gr_meshMe or gr_eosMode, and are stored in fortran
!! module Grid_data (in file Grid_data.F90). The other variables
!! are local to the specific routines and do not have the prefix "gr_"
!!
!!
!!***

subroutine Grid_markRefineDerefine()

  use Grid_data, ONLY : gr_refine_cutoff, gr_derefine_cutoff,&
                        gr_refine_filter,gr_refine_val_cutoff,&
                        gr_numRefineVars,gr_refine_var,gr_refineOnParticleCount,&
                        gr_blkList, gr_refine_level, gr_meshMe
  use tree, ONLY : newchild, refine, derefine, stay, nodetype,&
      lrefine, lrefine_max, parent, nchild,child, lnblocks
  use Grid_interface, ONLY : Grid_getBlkPtr, Grid_getListOfBlocks,&
      Grid_releaseBlkPtr,Grid_fillGuardCells,Grid_getMinCellSize
  use Driver_interface, ONLY: Driver_getSimTime
  use RuntimeParameters_interface, ONLY : RuntimeParameters_get
  use Simulation_data, ONLY: sim_objMass, sim_objPolyN, sim_objCentDen, np, obj_radius, &
      obj_ipos, sim_maxBlocks, obj_rhop, sim_useInitialPeakDensity
  use Multispecies_interface, ONLY:  Multispecies_getSumFrac, Multispecies_getSumInv, Multispecies_getAvg
  use Gravity_data, ONLY: grv_densCut, grv_obvec, grv_ptvec, grv_factor, grv_dynRefineMax, &
      grv_exactvec, grv_mpolevec
  use PhysicalConstants_interface, ONLY: PhysicalConstants_get
  use gr_mpoleData, ONLY: X_centerofmass, Y_centerofmass, Z_centerofmass
  use gr_isoMpoleData, ONLY: Xcm, Ycm, Zcm

  implicit none

#include "constants.h"
#include "Flash_mpi.h"
#include "Flash.h"
#include "Multispecies.h"

  double precision :: xcom, ycom, zcom
  double precision, dimension(:,:,:,:), pointer :: solnData
  double precision :: ref_cut,deref_cut,ref_filter,ref_val_cut,t
  double precision :: xcenter,ycenter,zcenter
  double precision :: maxptime,shrinkdur,box,zbox,dens_cut
  integer       :: l,iref,blkCount,lb,i,j
  logical :: doEos=.true.
  integer,parameter :: maskSize = NUNK_VARS+NDIM*NFACE_VARS
  logical,dimension(maskSize) :: gcMask
  double precision :: maxvals(MAXBLOCKS),maxvals_parent(MAXBLOCKS)
  integer :: nsend,nrecv,ierr,nextref,prev_refmax
  integer :: reqr(MAXBLOCKS),reqs(MAXBLOCKS)
  integer :: statr(MPI_STATUS_SIZE,MAXBLOCKS)
  integer :: stats(MPI_STATUS_SIZE,MAXBLOCKS)

  double precision :: polyk,mu, &
          x(np),y(np),yp(np),radius(np),rhop(np), &
          mass(np),prss(np),ebind(np),zopac(np), &
          rhom(np),zbeta(np),ztemp(np),exact(np), &
          xsurf,ypsurf,combo,min_cell
  double precision, dimension(NSPECIES) :: xn
  integer :: mode,iend,ipos,ref_level,max_blocks

#ifdef FLASH_MPOLE
    xcom = X_centerofmass
    ycom = Y_centerofmass
    zcom = Z_centerofmass
#else
    xcom = Xcm
    ycom = Ycm
    zcom = Zcm
#endif

  ! that are implemented in this file need values in guardcells

  if (sim_useInitialPeakDensity) then
      dens_cut = obj_rhop(1)
  else
      dens_cut = grv_densCut
  endif

  gcMask=.false.
  do i = 1,gr_numRefineVars
     iref = gr_refine_var(i)
     if (iref > 0) gcMask(iref) = .TRUE.
  end do

  call Grid_getMinCellSize(min_cell)
  call Grid_fillGuardCells(CENTER_FACES,ALLDIR,doEos=.true.,&
       maskSize=maskSize, mask=gcMask, makeMaskConsistent=.true.)

  newchild(:) = .FALSE.
  refine(:)   = .FALSE.
  derefine(:) = .FALSE.
  stay(:)     = .FALSE.

  !do l = 1,gr_numRefineVars
  !   iref = gr_refine_var(l)
  !   ref_cut = gr_refine_cutoff(l)
  !   deref_cut = gr_derefine_cutoff(l)
  !   ref_filter = gr_refine_filter(l)
  !   ref_val_cut = gr_refine_val_cutoff(l)
  !   call gr_markRefineDerefine(iref,ref_cut,deref_cut,ref_filter,&
  !       ref_val_cut)
  !end do

  call Driver_getSimTime(t)
  call Grid_getListOfBlocks(ACTIVE_BLKS, gr_blkList,blkCount)

  call RuntimeParameters_get('xmax',xcenter)      
  call RuntimeParameters_get('ymax',ycenter)      
  call RuntimeParameters_get('zmax',zcenter)      
  xcenter = xcenter / 2.
  ycenter = ycenter / 2.
  zcenter = zcenter / 2.

  if (t .eq. 0.0) then
      !write(*,*) 'entered sphere refine'
      call gr_markInRadius(xcenter,ycenter,zcenter,1.2*obj_radius(obj_ipos),lrefine_max,0)
  else
      Call MPI_ALLREDUCE (lnblocks,max_blocks,1,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,ierr)
      prev_refmax = grv_dynRefineMax
      if (max_blocks .gt. sim_maxBlocks) then
          grv_dynRefineMax = grv_dynRefineMax - 1
      endif
      do l = 1,gr_numRefineVars
          iref = gr_refine_var(l)
          ref_val_cut = dens_cut*gr_refine_val_cutoff(l)
          ref_level = min(gr_refine_level(l), grv_dynRefineMax)
          call gr_markVarThreshold(iref,ref_val_cut,0,ref_level)
      enddo

      !call gr_markInRectangle(xcenter-box,xcenter+box,ycenter-box,ycenter+box,&
      !   zcenter-zbox,zcenter+zbox,8,1,1)

      do l = 1,gr_numRefineVars
          iref = gr_refine_var(l)

          do i = 1, blkCount
             lb = gr_blkList(i)
             call Grid_getBlkPtr(lb,solnData,CENTER)
             maxvals(lb) = maxval(solnData(iref,:,:,:))
             call Grid_releaseBlkPtr(lb,solnData)
          end do

    !     Communicate maxvals of parents to their leaf children.
    !     Maximally refined children collect messages from parents.

          maxvals_parent(:) = 0.0
          nrecv = 0
          do i = 1, blkCount
             lb = gr_blkList(i)
             if (nodetype(lb) == LEAF .AND. lrefine(lb) == prev_refmax) then
                if(parent(1,lb).gt.-1) then
                   if (parent(2,lb).ne.gr_meshMe) then
                      nrecv = nrecv + 1
                      call MPI_IRecv(maxvals_parent(lb),1, &
                         FLASH_REAL, &
                         parent(2,lb), &
                         lb, &
                         MPI_COMM_WORLD, &
                         reqr(nrecv), &
                         ierr)
                   else
                      maxvals_parent(lb) = maxvals(parent(1,lb))
                   end if
                end if
             end if
          end do

          ! parents send maxvals to children

          nsend = 0
          do i = 1, blkCount
             lb = gr_blkList(i)
             if (nodetype(lb) == PARENT_BLK .AND. lrefine(lb) == prev_refmax-1) then
                do j = 1,nchild
                   if(child(1,j,lb).gt.-1) then
                      if (child(2,j,lb).ne.gr_meshMe) then
                         nsend = nsend + 1
                         call MPI_ISend(maxvals(lb), &
                            1, &
                            FLASH_REAL, &
                            child(2,j,lb), &  ! PE TO SEND TO
                            child(1,j,lb), &  ! THIS IS THE TAG
                            MPI_COMM_WORLD, &
                            reqs(nsend), &
                            ierr)
                      end if
                   end if
                end do
             end if
          end do

          if (nsend.gt.0) then
             call MPI_Waitall (nsend, reqs, stats, ierr)
          end if
          if (nrecv.gt.0) then
             call MPI_Waitall (nrecv, reqr, statr, ierr)
          end if

          nextref = 0
          do i = 1, gr_numRefineVars
              if (i .eq. l) cycle
              if (iref .ne. gr_refine_var(i)) cycle
              if (gr_refine_level(i) .gt. gr_refine_level(l)) cycle
              if (gr_refine_level(i) .gt. nextref) then
                  nextref = gr_refine_level(i)
                  exit
              endif
          enddo
    !!      maxvals_parent(:) = 0.0  ! <-- uncomment line for previous behavior
          do i = 1, blkCount
             lb = gr_blkList(i)
             if (nodetype(lb) == LEAF) then
                if (lrefine(lb) .gt. grv_dynRefineMax) then
                    refine(lb) = .false.
                    derefine(lb) = .true.
                elseif (lrefine(lb) .gt. nextref) then
                    if (maxvals(lb) < dens_cut*gr_refine_val_cutoff(l)) then
                        refine(lb)   = .false.
                        if (maxvals_parent(lb) < dens_cut*gr_refine_val_cutoff(l)) derefine(lb)   = .true.
                    endif
                endif
             end if
          enddo
      enddo

  endif

  ! Always refine maximally right around com to ensure innermost region of mpole solver doesn't change size
  call gr_markInRadius(grv_mpolevec(1), grv_mpolevec(2), grv_mpolevec(3), &
                       4.d0*min_cell,grv_dynRefineMax,0)
  call gr_markInRadius(grv_exactvec(1), grv_exactvec(2), grv_exactvec(3), &
                       4.d0*min_cell,grv_dynRefineMax,0)

  return
end subroutine Grid_markRefineDerefine
