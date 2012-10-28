#! /usr/bin/perl
#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Test;

AMC::Test->new('dir'=>__FILE__,'tex_engine'=>'pdflatex',
	       'grain'=>0.1,
	       'check_marks'=>{4=>13.3},
	       'verdict'=>'TOTAL : %S/%M => %s/%m',
	       'model'=>'(N).PDF',
	       'annote'=>[3,4],'annote_files'=>['0003.PDF','0004.PDF'],
	      )
  ->default_process;

