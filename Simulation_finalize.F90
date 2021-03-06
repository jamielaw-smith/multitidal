!!****f* source/Simulation/Simulation_finalize
!!
!! NAME
!!  Simulation_finalize
!!
!! SYNOPSIS
!!
!!  Simulation_finalize()
!!
!! DESCRIPTION
!!
!!  This dummy function cleans up the Simulation unit, deallocates memory, etc.
!!  However, as nothing needs to be done, only this stub is included.
!!
!! ARGUMENTS
!!
!!
!!
!!***

subroutine Simulation_finalize()

  use Simulation_data
  implicit none

  deallocate(ptvecs)
#ifdef LOADPROFILE
  deallocate(sim_table)
#endif
  deallocate(velsspec)
  deallocate(magsspec)

  return

end subroutine Simulation_finalize
