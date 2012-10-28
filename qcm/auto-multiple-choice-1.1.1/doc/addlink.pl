#! /usr/bin/perl
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

# pour ajouter un lien en premiere page de la doc PDF...

use File::Copy;

my $f=$ARGV[0];

if($f) {
    $fb=$f.'~';
    copy($f,$fb);
    open(ANCIEN,$fb);
    open(NOUVEAU,">$f");

    while(<ANCIEN>) {
	if(/\\DBKsubtitle/) {
	    s+\}$+ \\href{http://home.gna.org/auto-qcm/}{http://home.gna.org/auto-qcm/}}+;
	}
	print NOUVEAU;
    }

    close(ANCIEN);
    close(NOUVEAU);
}
