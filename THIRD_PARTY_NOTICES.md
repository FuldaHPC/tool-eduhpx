# Third-party notices (stub, to be completed before a release)

EduHPX is BSD-3-Clause (see LICENSE). It uses:

| Component | Licence | How it is used |
|---|---|---|
| Qt 6 (Core, Gui, Qml, Quick, Quick Controls 2, Quick Dialogs) | LGPL-3.0 (or commercial) | linked **dynamically**; the Qt licence texts and the offer of the Qt source are shipped with every binary package; users can replace the Qt libraries |

Nothing of HPX, Open MPI, Tracy, UCX or EduMPI is part of this repository or of its binaries. The patch for HPX and the measuring
MPI are distributed separately and carry their own licences (HPX: Boost Software License 1.0, Open MPI: BSD-3-Clause).

TODO before a release: copy the licence texts of the Qt modules that the installer deploys, and of the platform plugins.
