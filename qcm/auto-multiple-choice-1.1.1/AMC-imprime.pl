#! /usr/bin/perl
#
# Copyright (C) 2008-2012 Alexis Bienvenue <paamc@passoire.fr>
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
use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic;
use AMC::Exec;
use AMC::Data;
use AMC::Gui::Avancement;

my $data_dir="";
my $sujet='';
my $print_cmd='cupsdoprint %f';
my $progress='';
my $progress_id='';
my $debug='';
my $fich_nums='';
my $methode='CUPS';
my $imprimante='';
my $options='number-up=1';
my $output_file='';

GetOptions(
	   "data=s"=>\$data_dir,
	   "sujet=s"=>\$sujet,
	   "fich-numeros=s"=>\$fich_nums,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "print-command=s"=>\$print_cmd,
	   "methode=s"=>\$methode,
	   "imprimante=s"=>\$imprimante,
	   "output=s"=>\$output_file,
	   "options=s"=>\$options,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

my $commandes=AMC::Exec::new('AMC-imprime');
$commandes->signalise();

die "Needs data directory" if(!$data_dir);
die "Needs subject file" if(!$sujet);
die "Needs print command" if(!$print_cmd);

die "Needs output file" if($methode =~ /^file/i && !$output_file);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $layout=$data->module('layout');

my @es;

if($fich_nums) {
    open(NUMS,$fich_nums);
    while(<NUMS>) {
	push @es,$1 if(/^([0-9]+)$/);
    }
    close(NUMS);
} else {
  $layout->begin_read_transaction('prST');
  @es=$layout->query_list('students');
  $layout->end_transaction('prST');
}


my $n=0;
my $cups;
my $dest;

if($methode =~ /^cups/i) {
    if(check_install(module=>"Net::CUPS")) {
	load("Net::CUPS");
	debug_pm_version("Net::CUPS");
    } else {
	die "Needs Net::CUPS perl module for CUPS printing";
    }

    $cups=Net::CUPS->new();
    $dest=$cups->getDestination($imprimante);
    die "Can't access printer: $imprimante" if(!$dest);
    for my $o (split(/\s*,+\s*/,$options)) {
	my $on=$o;
	my $ov=1;
	if($o =~ /([^=]+)=(.*)/) {
	    $on=$1;
	    $ov=$2;
	}
	debug "Option : $on=$ov";
	$dest->addOption($on,$ov);
    }
}

for my $e (@es) {
    my $debut=1000000;
    my $fin=0;
    my $elong=sprintf("%04d",$e);
    $layout->begin_read_transaction('prSP');
    for ($layout->query_list('subjectpageForStudent',$e)) {
	$debut=$_ if($_<$debut);
	$fin=$_ if($_>$fin);
    }
    $layout->end_transaction('prSP');
    $n++;

    $tmp = File::Temp->new( DIR=>tmpdir(),UNLINK => 1, SUFFIX => '.pdf' );
    $fn=$tmp->filename();

    print "Student $e : pages $debut-$fin in file $fn...\n";

    $commandes->execute("gs","-dBATCH","-dNOPAUSE","-q","-sDEVICE=pdfwrite",
			"-sOutputFile=$fn",
			"-dFirstPage=$debut","-dLastPage=$fin",
			$sujet);

    $avance->progres(1/(2*(1+$#es)));

    if($methode =~ /^cups/i) {
	$dest->printFile($fn,"QCM : sheet $e");
    } elsif($methode =~ /^file/i) {
	my $f_dest=$output_file;
	$f_dest.="-%e.pdf" if($f_dest !~ /[%]e/);
	$f_dest =~ s/[%]e/$elong/g;

	debug "Moving to $f_dest";
	move($fn,$f_dest);
    } elsif($methode =~ /^command/i) {
	my @c=map { s/[%]f/$fn/g; s/[%]e/$elong/g; $_; } split(/\s+/,$print_cmd);

	#print STDERR join(' ',@c)."\n";
	$commandes->execute(@c);
    } else {
	die "Unknown method: $methode";
    }

    close($tmp);

    $avance->progres(1/(2*(1+$#es)));
}

$avance->fin();


