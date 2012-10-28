#! /usr/bin/perl
#
# Copyright (C) 2008,2011 Alexis Bienvenue <paamc@passoire.fr>
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

use Getopt::Long;
use AMC::Gui::Association;

my $cr_dir='';
my $liste='';
my $data_dir='';

GetOptions("cr=s"=>\$cr_dir,
	   "liste=s"=>\$liste,
	   "data=s"=>\$data_dir,
	   );

my $g=AMC::Gui::Association::new('cr'=>$cr_dir,
				 'liste'=>$liste,
				 'data_dir'=>$data_dir,
				 'global'=>1,
				 );

Gtk2->main;

