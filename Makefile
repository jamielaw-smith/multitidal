Simulation += Simulation_data.o orbit.o poly2.o
Driver += Orbit_update.o Total_force.o Bound_mass.o Orbit_energy.o odeint.o bsstep.o nr.o nrutil.o pzextr.o mmid.o
Grid += Grid_findExtrema.o
Gravity += Gravity_sendOutputData.o gr_mpoleGradTotPot.o gr_mpoleGradTotOldPot.o gr_mpoleGradPot.o \
		   gr_mpoleGradOldPot.o gr_mpoleCopyMoments.o gr_mpoleDeallocateOldMoments.o \
		   gr_mpoleCopyTotMoments.o gr_mpoleDeallocateTotMoments.o gr_isoMpoleData.o
IO += IO_writeOrbitInfo.o
Hydro += fss.o

bsstep.o : mmid.o pzextr.o nrutil.o
nrutil.o : nrtype.o
odeint.o : bsstep.o nrutil.o
mmid.o : nrutil.o
pzextr.o : nrutil.o
Orbit_update.o : nr.o odeint.o gr_mpoleGradTotPot.o gr_mpoleGradTotOldPot.o
Simulation_init.o : Simulation_data.o 
Simulation_initBlock.o : Simulation_data.o