# -*- perl -*-
#
# Copyright (C) 2011-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::DataModule::layout;

# AMC layout data management.

# This module is used to store (in a SQLite database) and handle all
# pages layouts: locations of all boxes, name field, marks on the
# pages.

# All coordinates are given in pixels, with (0,0)=TopLeft.

# TABLES:
#
# layout_page lists pages from the subject, with the following data:
#
# * student is the student number
#
# * page is the page number from the student copy (beginning from 1
#   for each student)
#
# * checksum is a number that is used to check that the student and
#   page numbers are properly recognized frm the scan
#
# * sourceid is an ID to get from table source the source information
#
# * subjectpage is the page number from the subject.pdf file
#   containing all subjects
#
# * dpi is the DPI resolution of the page
#
# * height,width are the page dimensions in pixels
#
# * markdiameter is the diameter of the four marks in the corners, in pixels
#
# layout_mark lists the marks positions on all the pages:
#
# * student,page identifies the page
#
# * corner is the corner number, from 1..4
#   (TopLeft=1, TopRight=2, BottomRight=3, BottomLeft=4)
#
# * x,y are the mark center coordinates (in pixels, (0,0)=TopLeft)
#
# layout_namefield lists the name fields on the pages:
#
# * student,page identifies the page
#
# * xmin,xmax,ymin,ymax give the box around the name field
#
# layout_box lists all the boxes to be ticked on all the pages:
#
# * student,page identifies the page
#
# * question is the question number. This is NOT the question number
#   that is printed on the question paper, but an internal question
#   number associated with question identifier from the LaTeX file
#   (strings used as the first argument of the \begin{question} or
#   \begin{questionmult} environment) as in table layout_question (see
#   next)
#
# * answer is the answer number for this question
#
# * xmin,xmax,ymin,ymax give the box coordinates
#
# * flags is an integer that contains the flags from BOX_FLAGS_* (see
#   below)
#
# layout_digit lists all the binary boxes to read student/page number
# and checksum from the scans (boxes white for digit 0, black for
# digit 1):
#
# * student,page identifies the page
#
# * numberid is the ID of the number to be read (1=student number,
#   2=page number, 3=checksum)
#
# * digitid is the digit ID (1 is the most significant bit)
#
# * xmin,xmax,ymin,ymax give the box coordinates
#
# layout_source describes where are all these information computed
# from:
#
# * sourceid refers to the same field in the layout_page table
#
# * src describes the file from which layout is read
#
# * timestamp is the time when the src file were read to populate the
#   layout_* tables
#
# layout_question describes the questions:
#
# * question is the question ID (see explanation in layout_box)
#
# * name is the question identifier from the LaTeX file

use Exporter qw(import);

use constant {
  BOX_FLAGS_DONTSCAN => 0x1,
  BOX_FLAGS_DONTANNOTATE => 0x2,
};

our @EXPORT_OK = qw(BOX_FLAGS_DONTSCAN BOX_FLAGS_DONTANNOTATE);
our %EXPORT_TAGS = ( 'flags' => [ qw/BOX_FLAGS_DONTSCAN BOX_FLAGS_DONTANNOTATE/ ],
		     );

use AMC::Basic;
use AMC::DataModule;
use XML::Simple;

@ISA=("AMC::DataModule");

sub version_current {
  return(2);
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

	# Upgrading from version 0 (empty database) to version 2 :
	# creates all the tables.

	debug "Creating layout tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("page")
		      ." (student INTEGER, page INTEGER, checksum INTEGER, sourceid INTEGER, subjectpage INTEGER, dpi REAL, width REAL, height REAL, markdiameter REAL, PRIMARY KEY (student,page))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("mark")
		      ." (student INTEGER, page INTEGER, corner INTEGER, x REAL, y REAL)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("namefield")
		      ." (student INTEGER, page INTEGER, xmin REAL, xmax REAL, ymin REAL, ymax REAL)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("box")
		      ." (student INTEGER, page INTEGER, question INTEGER, answer INTEGER, xmin REAL, xmax REAL, ymin REAL, ymax REAL, flags INTEGER DEFAULT 0)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("digit")
		      ." (student INTEGER, page INTEGER, numberid INTEGER, digitid INTEGER, xmin REAL, xmax REAL, ymin REAL, ymax REAL)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("source")
		      ." (sourceid INTEGER PRIMARY KEY, src TEXT, timestamp INTEGER)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("question")
		      ." (question INTEGER PRIMARY KEY, name TEXT)");
	$self->populate_from_xml;

	return(2);
    }
    if($old_version==1) {
      $self->sql_do("ALTER TABLE ".$self->table("box")
		   ." ADD COLUMN flags DEFAULT 0");
      return(2);
    }
    return('');
}

# populate_from_xml read the old format XML files (if any) and inserts
# them in the new SQLite database

sub populate_from_xml {
    my ($self)=@_;
    my $mep=$self->{'data'}->directory;
    $mep =~ s/\/[^\/]+\/?$/\/mep/;
    if(-d $mep) {
      $self->progression('begin',__"Fetching layout data from old format XML files...");

	opendir(DIR, $mep) || die "can't opendir $mep: $!";
	@xmls = grep { /\.xml$/ && -s "$mep/".$_ } 
	readdir(DIR);
	closedir DIR;

      my $frac=0;

	for my $f (@xmls) {
	    my $lay=XMLin("$mep/".$f,
			  ForceArray => 1,KeepRoot => 1, KeyAttr=> [ 'id' ]);

	    if($lay->{'mep'}) {
		my @st=stat("$mep/".$f);
		debug "Populating data from $f...";
		for my $laymep (keys %{$lay->{'mep'}}) {
		    my $l=$lay->{'mep'}->{$laymep};
		    my @epc;
		    if($laymep =~ /^\+([0-9]+)\/([0-9]+)\/([0-9]+)\+$/) {
			@epc=($1,$2,$3);
			$self->statement('NEWLayout')->execute(
			    @epc,
			    (map { $l->{$_} } (qw/page dpi tx ty diametremarque/)),
			    $self->source_id($l->{'src'},$st[9]));
		    }
		    my @lid=($epc[0],$epc[1]);
		    for my $n (@{$l->{'nom'}}) {
			$self->statement('NEWNameField')->execute(
			    @lid,map { $n->{$_} } (qw/xmin xmax ymin ymax/)
			    );
		    }
		    for my $c (@{$l->{'case'}}) {
			$self->statement('NEWBox')->execute(
			    @lid,(map { $c->{$_} } (qw/question reponse xmin xmax ymin ymax/)),0
			    );
		    }
		    for my $d (@{$l->{'chiffre'}}) {
			$self->statement('NEWDigit')->execute(
			    @lid,map { $d->{$_} } (qw/n i xmin xmax ymin ymax/)
			    );
		    }
		    my $marks=$l->{'coin'};
		    for my $i (keys %$marks) {
			$self->statement('NEWMark')->execute(
			    @lid,$i,map { $marks->{$i}->{$_}->[0] } (qw/x y/)
			    );
		    }
		}
	    }
	    $frac++;
	    $self->progression('fraction',$frac/($#xmls+1));
	  }
      $self->progression('end');
    }

    my $scoring_file=$self->{'data'}->directory;
    $scoring_file =~ s:/[^/]+/?$:/bareme.xml:;
    if(-f $scoring_file) {
      my $xml=XMLin($scoring_file,ForceArray => 1,KeyAttr=> [ 'id' ]);
      my @s=grep { /^[0-9]+$/ } (keys %{$xml->{'etudiant'}});
      for my $i (@s) {
	my $student=$xml->{'etudiant'}->{$i};
	for my $question (keys %{$student->{'question'}}) {
	  my $q=$student->{'question'}->{$question};
	  $self->question_name($question,$q->{'titre'});
	}
      }
    }
}

# defines all the SQL statements that will be used

sub define_statements {
    my ($self)=@_;
    $self->{'statements'}=
      {
       'CLEARPAGE'=>{'sql'=>"DELETE FROM ? WHERE student=? AND page=?"},
       'COUNT'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("page")},
       'StudentsCount'=>{'sql'=>"SELECT COUNT(*) FROM"
			 ." ( SELECT student FROM ".$self->table("page")
			 ."   GROUP BY student )"},
       'NEWLayout'=>
       {'sql'=>"INSERT INTO ".$self->table("page")
	." (student,page,checksum,subjectpage,dpi,width,height,markdiameter,sourceid)"
	." VALUES (?,?,?,?,?,?,?,?,?)"
       },
       'NEWMark'=>{'sql'=>"INSERT INTO ".$self->table("mark")
		   ." (student,page,corner,x,y) VALUES (?,?,?,?,?)"},
       'NEWBox'=>{'sql'=>"INSERT INTO ".$self->table("box")
		  ." (student,page,question,answer,xmin,xmax,ymin,ymax,flags)"
		  ." VALUES (?,?,?,?,?,?,?,?,?)"},
       'NEWDigit'=>{'sql'=>"INSERT INTO ".$self->table("digit")
		    ." (student,page,numberid,digitid,xmin,xmax,ymin,ymax)"
		    ." VALUES (?,?,?,?,?,?,?,?)"},
       'NEWNameField'=>{'sql'=>"INSERT INTO ".$self->table("namefield")
			." (student,page,xmin,xmax,ymin,ymax) VALUES (?,?,?,?,?,?)"},
       'NEWQuestion'=>{'sql'=>"INSERT INTO ".$self->table("question")
		       ." (question,name) VALUES (?,?)"},
       'IDS'=>{'sql'=>"SELECT student || ',' || page FROM ".$self->table("page")
	       ." ORDER BY student,page"},
       'FULLIDS'=>{'sql'=>"SELECT '+' || student || '/' || page || '/' || checksum || '+' FROM "
		   .$self->table("page")
		   ." ORDER BY student,page"},
       'PAGES_STUDENT_all'=>{'sql'=>"SELECT page FROM ".$self->table("page")
			     ." WHERE student=? ORDER BY page"},
       'STUDENTS'=>{'sql'=>"SELECT student FROM ".$self->table("page")
		    ." GROUP BY student ORDER BY student"},
       'Q_Flag'=>{'sql'=>"UPDATE ".$self->table("box")
		  ." SET flags=flags|? WHERE student=? AND question=?"},
       'A_Flags'=>{'sql'=>"SELECT flags FROM ".$self->table("box")
		  ." WHERE student=? AND question=? AND answer=?"},
       'PAGES_STUDENT_box'=>{'sql'=>"SELECT page FROM ".$self->table("box")
			     ." WHERE student=? GROUP BY student,page"},
       'PAGES_STUDENT_namefield'=>{'sql'=>"SELECT page FROM ".$self->table("namefield")
				   ." WHERE student=? GROUP BY student,page"},
       'PAGES_STUDENT_enter'=>
       {'sql'=>"SELECT page FROM ("
	."SELECT student,page FROM ".$self->table("box")." UNION "
	."SELECT student,page FROM ".$self->table("namefield")
	.") AS enter WHERE student=? GROUP BY student,page"},
       'PAGES_enter'=>
       {'sql'=>"SELECT student,page FROM ("
	."SELECT student,page FROM ".$self->table("box")." UNION "
	."SELECT student,page FROM ".$self->table("namefield")
	.") AS enter GROUP BY student,page ORDER BY student,page"},
       'MAX_enter'=>
       {'sql'=>"SELECT MAX(n) FROM"
	." ( SELECT COUNT(*) AS n FROM"
	."   ( SELECT student,page FROM ".$self->table("box")
	."     UNION SELECT student,page FROM ".$self->table("namefield")
	."   ) GROUP BY student )"},
       'DEFECT_NO_BOX'=>
       {'sql'=>"SELECT student FROM (SELECT student FROM ".$self->table("page")
	." GROUP BY student) AS list"
	." WHERE student>0 AND"
	."   NOT EXISTS(SELECT * FROM ".$self->table("box")." AS local"
	."              WHERE local.student=list.student)"},
       'DEFECT_NO_NAME'=>
       {'sql'=>"SELECT student FROM (SELECT student FROM ".$self->table("page")
	." GROUP BY student) AS list"
	." WHERE student>0 AND"
	."   NOT EXISTS(SELECT * FROM ".$self->table("namefield")." AS local"
	."              WHERE local.student=list.student)"},
       'DEFECT_SEVERAL_NAMES'=>
       {'sql'=>"SELECT student FROM (SELECT student,COUNT(*) AS n FROM "
	.$self->table("namefield")." GROUP BY student) AS counts WHERE n>1"},
       'pageFilename'=>{'sql'=>"SELECT student || '-' || page || '-' || checksum FROM "
			.$self->table("page")." WHERE student=? AND page=?"},
       'pageSubjectPage'=>{'sql'=>"SELECT subjectpage FROM ".$self->table("page")
			   ." WHERE student=? AND page=?"},
       'students'=>{'sql'=>"SELECT student FROM ".$self->table("page")
		    ." GROUP BY student"},
       'subjectpageForStudent'=>{'sql'=>"SELECT subjectpage FROM ".$self->table("page")
				 ." WHERE student=? ORDER BY page"},
       'studentPage'=>{'sql'=>"SELECT student,page FROM ".$self->table("page")
		       ." LIMIT 1"},
       'dims'=>{'sql'=>"SELECT width,height,markdiameter FROM "
		.$self->table("page")
		." WHERE student=? AND page=?"},
       'mark'=>{'sql'=>"SELECT x,y FROM ".$self->table("mark")
		." WHERE student=? AND page=? AND corner=?"},
       'pageInfo'=>{'sql'=>"SELECT * FROM ".$self->table("page")
		    ." WHERE student=? AND page=?"},
       'digitInfo'=>{'sql'=>"SELECT * FROM ".$self->table("digit")
		     ." WHERE student=? AND page=?"},
       'boxInfo'=>{'sql'=>"SELECT * FROM ".$self->table("box")
		   ." WHERE student=? AND page=?"},
       'namefieldInfo'=>{'sql'=>"SELECT * FROM ".$self->table("namefield")
			 ." WHERE student=? AND page=?"},
       'exists'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("page")
		  ." WHERE student=? AND page=? AND checksum=?"},
       'questionName'=>{'sql'=>"SELECT name FROM ".$self->table("question")
			." WHERE question=?"},
       'sourceID'=>{'sql'=>"SELECT sourceid FROM ".$self->table("source")
		    ." WHERE src=? AND timestamp=?"},
       'NEWsource'=>{'sql'=>"INSERT INTO ".$self->table("source")
		     ." (src,timestamp) VALUES(?,?)"},
       'checkPosDigits'=>
       {'sql'=>"SELECT a.student AS student_a,b.student AS student_b,"
	."         a.page AS page_a, b.page AS page_b,* FROM"
	." (SELECT * FROM"
	."   (SELECT * FROM ".$self->table("digit")
	."    ORDER BY student DESC,page DESC)"
	."  GROUP BY numberid,digitid) AS a,"
	."  ".$self->table("digit")." AS b"
	." ON a.digitid=b.digitid AND a.numberid=b.numberid"
	."    AND (abs(a.xmin-b.xmin)>? OR abs(a.xmax-b.xmax)>?"
	."         OR abs(a.ymin-b.ymin)>? OR abs(a.ymax-b.ymax)>?)"
	." LIMIT 1"},
       'checkPosMarks'=>
       {'sql'=>"SELECT a.student AS student_a,b.student AS student_b,"
	."         a.page AS page_a, b.page AS page_b,* FROM"
	." (SELECT * FROM"
	."   (SELECT * FROM ".$self->table("mark")
	."    ORDER BY student DESC,page DESC)"
	."  GROUP BY corner) AS a,"
	."  ".$self->table("mark")." AS b"
	." ON a.corner=b.corner"
	."    AND (abs(a.x-b.x)>? OR abs(a.y-b.y)>?)"
	." LIMIT 1"},
      };
}

# clear_page_layout($student,$page) clears all the layout data for a
# given page

sub clear_page_layout {
    my ($self,$student,$page)=@_;
    for my $t (qw/page box namefield digit/) {
	$self->statement('CLEARPAGE')->execute($self->table($t),$student,$page);
    }
}

# random_studentPage returns an existing student,page couple

sub random_studentPage {
    my ($self)=@_;
    return($self->dbh->selectrow_array($self->statement('studentPage')));
}

# exists returns the number of pages with coresponding student, page
# and checksum. The result should be 0 (no such page in the subject)
# or 1.

sub exists {
    my ($self,$student,$page,$checksum)=@_;
    return($self->sql_single($self->statement('exists'),
			     $student,$page,$checksum));
}

# dims($student,$page) returns a (width,height,markdiameter) array for the given
# (student,page) page.

sub dims {
    my ($self,$student,$page)=@_;
    return($self->dbh->selectrow_array($self->statement('dims'),{},
				       $student,$page));
}

# all_marks returns x,y coordinates for the four corner marks on the
# requested page: (x1,y1,x2,y2,x3,y3,x4,y4)

sub all_marks {
    my ($self,$student,$page)=@_;
    my @r=();
    for my $corner (1..4) {
	push @r,$self->dbh->selectrow_array($self->statement('mark'),{},
	    $student,$page,$corner);
    }
    return(@r);
}

# page_count returns the number of pages

sub pages_count {
    my ($self)=@_;
    return($self->sql_single($self->statement('COUNT')));
}

# page_count returns the number of different students

sub students_count {
    my ($self)=@_;
    return($self->sql_single($self->statement('StudentsCount')));
}

# ids returns student,page string for all pages

sub ids {
    my ($self)=@_;
    return($self->sql_list($self->statement('IDS')));
}

# full_ids returns +student/page/checksum+ string for all pages

sub full_ids {
    my ($self)=@_;
    return($self->sql_list($self->statement('FULLIDS')));
}

# page_info returns a HASH reference containing all fields in the
# layout_page row corresponding to the student,page page.

sub page_info {
    my ($self,$student,$page)=@_;
    return($self->dbh->selectrow_hashref(
	       $self->statement('pageInfo'),{},$student,$page));
}

# pages_for_student($student,[%options]) returns a list of the page
# numbers on the subject (starting from 1 for each student) for this
# student. With 'select'=>'box' as an option, restricts to the pages
# where at least one box to be filled is present. With
# 'select'=>'namefield', restricts to the pages where the name field
# is. With 'select'=>'enter', restricts to the pages where the
# students has to write something (where there are boxes or name
# field).

sub pages_for_student {
    my ($self,$student,%oo)=@_;
    $oo{'select'}='all' if(!$oo{'select'});
    return($self->sql_list($self->statement('PAGES_STUDENT_'.$oo{'select'}),
			   $student));
}

# students returns the list of the students numbers.

sub students {
    my ($self)=@_;
    return($self->sql_list($self->statement('STUDENTS')));
}

# defects($delta) returns a hash of the defects found in the subject:
#
# * {'NO_BOX} is a pointer on an array containing all the student
#   numbers for which there is no box to be filled in the subject
#
# * {'NO_NAME'} is a pointer on an array containing all the student
#   numbers for which there is no name field
#
# * {'SEVERAL_NAMES'} is a pointer on an array containing all the student
#   numbers for which there is more than one name field
#
# * {'DIFFERENT_POSITIONS'} is a pointer to a hash returned by
#   check_positions($delta)
sub defects {
    my ($self,$delta)=@_;
    $delta=0.1 if(!defined($delta));
    my %r=();
    for my $type (qw/NO_BOX NO_NAME SEVERAL_NAMES/) {
	my @s=$self->sql_list($self->statement('DEFECT_'.$type));
	$r{$type}=[@s] if(@s);
    }
    my $pos=$self->check_positions($delta);
    $r{'DIFFERENT_POSITIONS'}=$pos if($pos);
    return(%r);
}

# source_id($src,$timestamp) looks in the table source if a row with
# values ($src,$timestamp) already exists. If it does, source_id
# returns the sourceid value for this row. If not, it creates a row
# with these values and returns the primary key sourceid for this new
# row.

sub source_id {
    my ($self,$src,$timestamp)=@_;
    my $sid=$self->sql_single($self->statement('sourceID'),$src,$timestamp);
    if($sid) {
	return($sid);
    } else {
	$self->statement('NEWsource')->execute($src,$timestamp);
	return($self->dbh->sqlite_last_insert_rowid());
    }
}

# question_name($question) returns the question name for question
# number $question
#
# question_name($question,$name) sets the question name (identifier
# string from LaTeX file) for question number $question.

sub question_name {
    my ($self,$question,$name)=@_;
    if(defined($name)) {
      my $n=$self->question_name($question);
      if($n) {
	if($n ne $name) {
	  debug "ERROR: question ID=$question with different names ($n/$name)";
	}
      } else {
	$self->statement('NEWQuestion')->execute($question,$name);
      }
    } else {
      return($self->sql_single($self->statement('questionName'),
			       $question));
    }
}

# clear_all clears all the layout data tables.

sub clear_all {
    my ($self)=@_;
    for my $t (qw/page mark namefield box digit source/) {
	$self->sql_do("DELETE FROM ".$self->table($t));
    }
}

# get_pages returns a reference to an array like
# [[student_1,page_1],[student_2,page_2]] listing the pages where
# something has to be entered by the students (either answers boxes or
# name field).

sub get_pages {
  my ($self,$add_copy)=@_;
  my $r=$self->dbh
    ->selectall_arrayref($self->statement('PAGES_enter'));
  if(defined($add_copy)) {
    for(@$r) { push @{$_},0 }
  }
  return $r;
}

# check_positions($delta) checks if all pages has the same positions
# for marks and binary digits boxes. If this is the case (this SHOULD
# allways be the case), check_positions returns undef. If not,
# check_positions returns a hashref
# {student_a=>S1,page_a=>P1,student_b=>S2,page_b=>P2} showing an
# example for which (S1,P1) has not the same positions as (S2,P2)
# (with difference over $delta for at least one coordinate).

sub check_positions {
  my ($self,$delta)=@_;
  my $r=$self->dbh->selectrow_hashref($self->statement('checkPosDigits'),{},
				      $delta,$delta,$delta,$delta);
  return($r) if($r);
  $r=$self->dbh->selectrow_hashref($self->statement('checkPosMarks'),{},
				   $delta,$delta);
  return($r);
}

# max_enter() returns the maximum of enter pages (pages where the
# students are to write something: either boxes to tick either name
# field) per student.

sub max_enter {
  my ($self)=@_;
  return($self->sql_single($self->statement("MAX_enter")));
}

# add_question_flag($student,$question,$flag) adds the flag to all
# answers boxes for a particular student and question.

sub add_question_flag {
  my ($self,$student,$question,$flag)=@_;
  $self->statement('Q_Flag')->execute($flag,$student,$question);
}

# get_box_glags($student,$question,$answer) returns the flags for the
# corresponding box.

sub get_box_flags {
  my ($self,$student,$question,$answer)=@_;
  return($self->sql_single($self->statement('A_Flags'),
			   $student,$question,$answer));
}

1;
