#!/usr/bin/perl
###########################################################################
# Java API Compliance Checker (Java ACC) 1.1
# A tool for checking backward compatibility of a Java library API
#
# Copyright (C) 2011 Russian Linux Verification Center
# Copyright (C) 2011-2012 ROSA Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  Linux, FreeBSD, Mac OS X, MS Windows
#
# REQUIREMENTS
# ============
#  Linux, FreeBSD, Mac OS X
#    - JDK (javap, javac)
#    - Perl (5.8-5.14)
#
#  MS Windows
#    - JDK (javap, javac)
#    - Active Perl (5.8-5.14)
#  
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License or the GNU Lesser
# General Public License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# and the GNU Lesser General Public License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case");
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(abs_path cwd);
use Data::Dumper;
use Config;

my $TOOL_VERSION = "1.1";
my $API_DUMP_VERSION = "1.0";
my $API_DUMP_MAJOR = majorVersion($API_DUMP_VERSION);

my ($Help, $ShowVersion, %Descriptor, $TargetLibraryName, $CheckSeparately,
$GenerateDescriptor, $TestSystem, $DumpAPI, $ClassListPath, $ClientPath,
$StrictCompat, $DumpVersion, $BinaryOnly, $TargetLibraryFullName, $CheckImpl,
%TargetVersion, $SourceOnly, $ShortMode, $KeepInternal, $OutputReportPath,
$BinaryReportPath, $SourceReportPath, $Browse, $Debug, $Quick);

my $CmdName = get_filename($0);
my $OSgroup = get_OSgroup();
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);
my $MAX_ARGS = ($OSgroup eq "windows")?100:1200;

my %OS_Archive = (
    "windows"=>"zip",
    "default"=>"tar.gz"
);

my %ERROR_CODE = (
    # Compatible verdict
    "Compatible"=>0,
    "Success"=>0,
    # Incompatible verdict
    "Incompatible"=>1,
    # Undifferentiated error code
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Invalid input API dump
    "Invalid_Dump"=>7,
    # Incompatible version of API dump
    "Dump_Version"=>8,
    # Cannot find a module
    "Module_Error"=>9
);

my %HomePage = (
    "Wiki"=>"http://ispras.linuxbase.org/index.php/Java_API_Compliance_Checker",
    "Dev"=>"https://github.com/lvc/japi-compliance-checker"
);

my $ShortUsage = "Java API Compliance Checker (Java ACC) $TOOL_VERSION
A tool for checking backward compatibility of a Java library API
Copyright (C) 2012 ROSA Laboratory
License: GNU LGPL or GNU GPL

Usage: $CmdName [options]
Example: $CmdName -old OLD.jar -new NEW.jar

More info: $CmdName --help\n";

if($#ARGV==-1) {
    print $ShortUsage;
    exit(0);
}

foreach (2 .. $#ARGV)
{ # correct comma separated options
    if($ARGV[$_-1] eq ",") {
        $ARGV[$_-2].=",".$ARGV[$_];
        splice(@ARGV, $_-1, 2);
    }
    elsif($ARGV[$_-1]=~/,\Z/) {
        $ARGV[$_-1].=$ARGV[$_];
        splice(@ARGV, $_, 1);
    }
    elsif($ARGV[$_]=~/\A,/
    and $ARGV[$_] ne ",") {
        $ARGV[$_-1].=$ARGV[$_];
        splice(@ARGV, $_, 1);
    }
}

GetOptions("h|help!" => \$Help,
  "v|version!" => \$ShowVersion,
  "dumpversion!" => \$DumpVersion,
#general options
  "l|lib|library=s" => \$TargetLibraryName,
  "d1|old|o=s" => \$Descriptor{1}{"Path"},
  "d2|new|n=s" => \$Descriptor{2}{"Path"},
#extra options
  "client|app=s" => \$ClientPath,
  "binary!" => \$BinaryOnly,
  "source!" => \$SourceOnly,
  "check-implementation!" => \$CheckImpl,
  "v1|version1=s" => \$TargetVersion{1},
  "v2|version2=s" => \$TargetVersion{2},
  "s|strict!" => \$StrictCompat,
  "keep-internal!" => \$KeepInternal,
  "dump|dump-api=s" => \$DumpAPI,
  "classes-list=s" => \$ClassListPath,
  "short" => \$ShortMode,
  "d|template!" => \$GenerateDescriptor,
  "report-path=s" => \$OutputReportPath,
  "bin-report-path=s" => \$BinaryReportPath,
  "src-report-path=s" => \$SourceReportPath,
  "quick!" => \$Quick,
#other options
  "test!" => \$TestSystem,
  "debug!" => \$Debug,
  "l-full|lib-full=s" => \$TargetLibraryFullName,
  "b|browse=s" => \$Browse
) or ERR_MESSAGE();

sub ERR_MESSAGE()
{
    print "\n".$ShortUsage;
    exit($ERROR_CODE{"Error"});
}

my $AR_EXT = getAR_EXT($OSgroup);

my $HelpMessage="
NAME:
  Java API Compliance Checker ($CmdName)
  Check backward compatibility of a Java library API

DESCRIPTION:
  Java API Compliance Checker (Java ACC) is a tool for checking backward
  binary/source compatibility of a Java library API. The tool checks classes
  declarations of old and new versions and analyzes changes that may break
  compatibility: removed class members, added abstract methods, etc. Breakage
  of the binary compatibility may result in crashing or incorrect behavior of
  existing clients built with an old version of a library if they run with a
  new one. Breakage of the source compatibility may result in recompilation
  errors with a new library version.

  Java ACC is intended for library developers and operating system maintainers
  who are interested in ensuring backward compatibility (i.e. allow old clients
  to run or to be recompiled with a new version of a library).

  This tool is free software: you can redistribute it and/or modify it
  under the terms of the GNU LGPL or GNU GPL.

USAGE:
  $CmdName [options]

EXAMPLE:
  $CmdName -old OLD.jar -new NEW.jar
    OR
  $CmdName -lib NAME -old OLD.xml -new NEW.xml
  OLD.xml and NEW.xml are XML-descriptors:

    <version>
        1.0
    </version>
    
    <archives>
        /path1/to/JAR(s)/
        /path2/to/JAR(s)/
        ...
    </archives>

INFORMATION OPTIONS:
  -h|-help
      Print this help.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -l|-lib|-library <name>
      Library name (without version).
      It affects only on the path and the title of the report.

  -d1|-old|-o <path(s)>
      Descriptor of 1st (old) library version.
      It may be one of the following:
      
         1. Java ARchive (*.jar)
         2. XML-descriptor (VERSION.xml file):

              <version>
                  1.0
              </version>
              
              <archives>
                  /path1/to/JAR(s)/
                  /path2/to/JAR(s)/
                   ...
              </archives>

                 ... (XML-descriptor template
                         may be generated by -d option)
         
         3. API dump generated by -dump option
         4. Directory with Java ARchives
         5. Comma separated list of Java ARchives
         6. Comma separated list of directories with Java ARchives

      If you are using 1, 4-6 descriptor types then you should
      specify version numbers with -v1 <num> and -v2 <num> options too.

      If you are using *.jar as a descriptor then the tool will try to
      get implementation version from MANIFEST.MF file.

  -d2|-new|-n <path(s)>
      Descriptor of 2nd (new) library version.

EXTRA OPTIONS:
  -client|-app <path>
      This option allows to specify the client Java ARchive that should be
      checked for portability to the new library version.
      
  -binary
      Show \"Binary\" compatibility problems only.
      Generate report to \"bin_compat_report.html\".
      
  -source
      Show \"Source\" compatibility problems only.
      Generate report to \"src_compat_report.html\".
      
  -check-implementation
      Compare implementation code (method\'s body) of Java classes.
      Add \'Problems with Implementation\' section to the report.
      
  -v1|-version1 <num>
      Specify 1st API version outside the descriptor. This option is needed
      if you have prefered an alternative descriptor type (see -d1 option).
      
      In general case you should specify it in the XML descriptor:
          <version>
              VERSION
          </version>

  -v2|-version2 <num>
      Specify 2nd library version outside the descriptor.
      
  -s|-strict
      Treat all API compatibility warnings as problems.
      
  -dump|-dump-api <descriptor>
      Dump library API to gzipped TXT format file. You can transfer it
      anywhere and pass instead of the descriptor. Also it may be used
      for debugging the tool. Compatible dump versions: $API_DUMP_MAJOR.0<=V<=$API_DUMP_VERSION
      
      
  -classes-list <path>
      This option allows to specify a file with a list of classes that should
      be checked, other classes will not be checked.
      
  -short <path>
      Generate short report without 'Added Methods' section.
      
  -d|-template
      Create XML descriptor template ./VERSION.xml

  -report-path <path>
      Path to compatibility report.
      Default: 
          compat_reports/<library name>/<v1>_to_<v2>/compat_report.html

  -bin-report-path <path>
      Path to \"Binary\" compatibility report.
      Default: 
          compat_reports/<library name>/<v1>_to_<v2>/bin_compat_report.html

  -src-report-path <path>
      Path to \"Source\" compatibility report.
      Default: 
          compat_reports/<library name>/<v1>_to_<v2>/src_compat_report.html

  -quick
      Quick analysis.
      Disabled:
        - analysis of method parameter names
        - analysis of class field values
        - analysis of usage of added abstract methods

OTHER OPTIONS:
  -test
      Run internal tests. Create two incompatible versions of a sample library
      and run the tool to check them for compatibility. This option allows to
      check if the tool works correctly in the current environment.

  -debug
      Debugging mode. Print debug info on the screen. Save intermediate
      analysis stages in the debug directory:
          debug/<library>/<version>/

      Also consider using --dump option for debugging the tool.

  -l-full|-lib-full <name>
      Change library name in the report title to <name>. By default
      will be displayed a name specified by -l option.

  -b|-browse <program>
      Open report(s) in the browser (firefox, opera, etc.).

REPORT:
    Compatibility report will be generated to:
        compat_reports/<library name>/<v1>_to_<v2>/compat_report.html
      
EXIT CODES:
    0 - Compatible. The tool has run without any errors.
    non-zero - Incompatible or the tool has run with errors.

REPORT BUGS TO:
    Andrey Ponomarenko <aponomarenko\@rosalab.ru>

MORE INFORMATION:
    ".$HomePage{"Wiki"}."
    ".$HomePage{"Dev"}."\n\n";

sub HELP_MESSAGE()
{ # -help
    print $HelpMessage."\n\n";
}

my $Descriptor_Template = "
<?xml version=\"1.0\" encoding=\"utf-8\"?>
<descriptor>

/* Primary sections */

<version>
    /* Version of the library */
</version>

<archives>
    /* The list of paths to Java ARchives and/or
       directories with archives, one per line */
</archives>

/* Optional sections */

<skip_packages>
    /* The list of packages, that
       should not be checked, one per line */
</skip_packages>

<packages>
    /* The list of packages, that
       should be checked, one per line.
       Other packages will not be checked. */
</packages>

</descriptor>";

my %TypeProblems_Kind=(
    "Binary"=>{
        "NonAbstract_Class_Added_Abstract_Method"=>"High",
        "Abstract_Class_Added_Abstract_Method"=>"Medium",
        "Class_Removed_Abstract_Method"=>"High",
        "Interface_Added_Abstract_Method"=>"Medium",
        "Interface_Removed_Abstract_Method"=>"High",
        "Removed_Class"=>"High",
        "Removed_Interface"=>"High",
        "Class_Method_Became_Abstract"=>"High",
        "Class_Method_Became_NonAbstract"=>"Low",
        "Added_Super_Class"=>"Low",
        "Abstract_Class_Added_Super_Abstract_Class"=>"Medium",
        "Removed_Super_Class"=>"Medium",
        "Changed_Super_Class"=>"Medium",
        "Abstract_Class_Added_Super_Interface"=>"Medium",
        "Class_Removed_Super_Interface"=>"High",
        "Interface_Added_Super_Interface"=>"Medium",
        "Interface_Added_Super_Constant_Interface"=>"Low",
        "Interface_Removed_Super_Interface"=>"High",
        "Class_Became_Interface"=>"High",
        "Interface_Became_Class"=>"High",
        "Class_Became_Final"=>"High",
        "Class_Became_Abstract"=>"High",
        "Class_Added_Field"=>"Safe",
        "Interface_Added_Field"=>"Safe",
        "Removed_NonConstant_Field"=>"High",
        "Removed_Constant_Field"=>"Low",
        "Renamed_Field"=>"High",
        "Renamed_Constant_Field"=>"Low",
        "Changed_Field_Type"=>"High",
        "Changed_Field_Access"=>"High",
        "Changed_Final_Field_Value"=>"Medium",
        "Field_Became_Final"=>"Medium",
        "Field_Became_NonFinal"=>"Low",
        "NonConstant_Field_Became_Static"=>"High",
        "NonConstant_Field_Became_NonStatic"=>"High",
        "Class_Overridden_Method"=>"Low",
        "Class_Method_Moved_Up_Hierarchy"=>"Low"
    },
    "Source"=>{
        "NonAbstract_Class_Added_Abstract_Method"=>"High",
        "Abstract_Class_Added_Abstract_Method"=>"High",
        "Interface_Added_Abstract_Method"=>"High",
        "Class_Removed_Abstract_Method"=>"High",
        "Interface_Removed_Abstract_Method"=>"High",
        "Removed_Class"=>"High",
        "Removed_Interface"=>"High",
        "Class_Method_Became_Abstract"=>"High",
        "Added_Super_Class"=>"Low",
        "Abstract_Class_Added_Super_Abstract_Class"=>"High",
        "Removed_Super_Class"=>"Medium",
        "Changed_Super_Class"=>"Medium",
        "Abstract_Class_Added_Super_Interface"=>"High",
        "Class_Removed_Super_Interface"=>"High",
        "Interface_Added_Super_Interface"=>"High",
        "Interface_Added_Super_Constant_Interface"=>"Low",
        "Interface_Removed_Super_Interface"=>"High",
        "Interface_Removed_Super_Constant_Interface"=>"High",
        "Class_Became_Interface"=>"High",
        "Interface_Became_Class"=>"High",
        "Class_Became_Final"=>"High",
        "Class_Became_Abstract"=>"High",
        "Class_Added_Field"=>"Safe",
        "Interface_Added_Field"=>"Safe",
        "Removed_NonConstant_Field"=>"High",
        "Removed_Constant_Field"=>"High",
        "Renamed_Field"=>"High",
        "Renamed_Constant_Field"=>"High",
        "Changed_Field_Type"=>"High",
        "Changed_Field_Access"=>"High",
        "Field_Became_Final"=>"Medium",
        "Constant_Field_Became_NonStatic"=>"High",
        "NonConstant_Field_Became_NonStatic"=>"High"
    }
);

my %MethodProblems_Kind=(
    "Binary"=>{
        "Added_Method"=>"Safe",
        "Removed_Method"=>"High",
        "Method_Became_Static"=>"High",
        "Method_Became_NonStatic"=>"High",
        "NonStatic_Method_Became_Final"=>"Medium",
        "Changed_Method_Access"=>"High",
        "Method_Became_Synchronized"=>"Low",
        "Method_Became_NonSynchronized"=>"Low",
        "Method_Became_Abstract"=>"High",
        "Method_Became_NonAbstract"=>"Low",
        "NonAbstract_Method_Added_Checked_Exception"=>"Low",
        "NonAbstract_Method_Removed_Checked_Exception"=>"Low",
        "Added_Unchecked_Exception"=>"Low",
        "Removed_Unchecked_Exception"=>"Low",
        "Variable_Arity_To_Array"=>"Low",# not implemented yet
        "Changed_Method_Return_From_Void"=>"High"
    },
    "Source"=>{
        "Added_Method"=>"Safe",
        "Removed_Method"=>"High",
        "Method_Became_Static"=>"Low",
        "Method_Became_NonStatic"=>"High",
        "Static_Method_Became_Final"=>"Medium",
        "NonStatic_Method_Became_Final"=>"Medium",
        "Changed_Method_Access"=>"High",
        "Method_Became_Abstract"=>"High",
        "Abstract_Method_Added_Checked_Exception"=>"Medium",
        "NonAbstract_Method_Added_Checked_Exception"=>"Medium",
        "Abstract_Method_Removed_Checked_Exception"=>"Medium",
        "NonAbstract_Method_Removed_Checked_Exception"=>"Medium"
    }
);

my %KnownRuntimeExceptions= map {$_=>1} (
# To separate checked- and unchecked- exceptions
    "java.lang.AnnotationTypeMismatchException",
    "java.lang.ArithmeticException",
    "java.lang.ArrayStoreException",
    "java.lang.BufferOverflowException",
    "java.lang.BufferUnderflowException",
    "java.lang.CannotRedoException",
    "java.lang.CannotUndoException",
    "java.lang.ClassCastException",
    "java.lang.CMMException",
    "java.lang.ConcurrentModificationException",
    "java.lang.DataBindingException",
    "java.lang.DOMException",
    "java.lang.EmptyStackException",
    "java.lang.EnumConstantNotPresentException",
    "java.lang.EventException",
    "java.lang.IllegalArgumentException",
    "java.lang.IllegalMonitorStateException",
    "java.lang.IllegalPathStateException",
    "java.lang.IllegalStateException",
    "java.lang.ImagingOpException",
    "java.lang.IncompleteAnnotationException",
    "java.lang.IndexOutOfBoundsException",
    "java.lang.JMRuntimeException",
    "java.lang.LSException",
    "java.lang.MalformedParameterizedTypeException",
    "java.lang.MirroredTypeException",
    "java.lang.MirroredTypesException",
    "java.lang.MissingResourceException",
    "java.lang.NegativeArraySizeException",
    "java.lang.NoSuchElementException",
    "java.lang.NoSuchMechanismException",
    "java.lang.NullPointerException",
    "java.lang.ProfileDataException",
    "java.lang.ProviderException",
    "java.lang.RasterFormatException",
    "java.lang.RejectedExecutionException",
    "java.lang.SecurityException",
    "java.lang.SystemException",
    "java.lang.TypeConstraintException",
    "java.lang.TypeNotPresentException",
    "java.lang.UndeclaredThrowableException",
    "java.lang.UnknownAnnotationValueException",
    "java.lang.UnknownElementException",
    "java.lang.UnknownEntityException",
    "java.lang.UnknownTypeException",
    "java.lang.UnmodifiableSetException",
    "java.lang.UnsupportedOperationException",
    "java.lang.WebServiceException",
    "java.lang.WrongMethodTypeException"
);

my %Slash_Type=(
    "default"=>"/",
    "windows"=>"\\"
);

my $SLASH = $Slash_Type{$OSgroup}?$Slash_Type{$OSgroup}:$Slash_Type{"default"};

my %OS_AddPath=(
# this data needed if tool can't detect it automatically
"macos"=>{
    "bin"=>{"/Developer/usr/bin"=>1}},
"beos"=>{
    "bin"=>{"/boot/common/bin"=>1,"/boot/system/bin"=>1,"/boot/develop/abi"=>1}}
);

#Global variables
my %RESULT;
my $ExtractCounter = 0;
my %Cache;
my $TOP_REF = "<a style='font-size:11px;' href='#Top'>to the top</a>";
my %DEBUG_PATH;

#Types
my %TypeInfo;
my $TypeID = 0;
my %CheckedTypes;
my %TName_Tid;
my %Class_Constructed;

#Classes
my %ClassList_User;
my %UsedMethods_Client;
my %UsedFields_Client;
my %LibClasses;
my %LibArchives;
my %Class_Methods;
my %Class_AbstractMethods;
my %Class_Fields;
my %MethodInvoked;
my %ClassMethod_AddedInvoked;
my %FieldUsed;

#Methods
my %CheckedMethods;
my %MethodBody;
my %tr_name;

#Merging
my %MethodInfo;
my $Version;
my %AddedMethod_Abstract;
my %RemovedMethod_Abstract;
my %ChangedReturnFromVoid;
my %SkipPackages;
my %KeepPackages;

#Report
my %Type_MaxPriority;

#Recursion locks
my @RecurSymlink;
my @RecurTypes;

#System
my %SystemPaths;
my %DefaultBinPaths;

#Problem descriptions
my %CompatProblems;
my %ImplProblems;
my %TotalAffected;

#Rerort
my $ContentID = 1;
my $ContentSpanStart = "<span class=\"section\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanStart_Affected = "<span class=\"section_affected\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanEnd = "</span>\n";
my $ContentDivStart = "<div id=\"CONTENT_ID\" style=\"display:none;\">\n";
my $ContentDivEnd = "</div>\n";
my $Content_Counter = 0;

#Modes
my $JoinReport = 1;
my $DoubleReport = 0;

sub get_CmdPath($)
{
    my $Name = $_[0];
    return "" if(not $Name);
    return $Cache{"get_CmdPath"}{$Name} if(defined $Cache{"get_CmdPath"}{$Name});
    if(my $DefaultPath = get_CmdPath_Default($Name))
    {
        $Cache{"get_CmdPath"}{$Name} = $DefaultPath;
        return $Cache{"get_CmdPath"}{$Name};
    }
    foreach my $Path (sort {length($a)<=>length($b)} keys(%{$SystemPaths{"bin"}}))
    {
        if(-f $Path."/".$Name or -f $Path."/".$Name.".exe") {
            $Cache{"get_CmdPath"}{$Name} = joinPath($Path,$Name);
            return $Cache{"get_CmdPath"}{$Name};
        }
    }
    $Cache{"get_CmdPath"}{$Name} = "";
    return "";
}

sub get_CmdPath_Default($)
{# search in PATH
    my $Name = $_[0];
    return "" if(not $Name);
    return $Cache{"get_CmdPath_Default"}{$Name} if(defined $Cache{"get_CmdPath_Default"}{$Name});
    if($Name eq "find")
    {# special case: search for "find" utility
        if(`find . -maxdepth 0 2>$TMP_DIR/null`) {
            $Cache{"get_CmdPath_Default"}{$Name} = "find";
            return "find";
        }
    }
    if(get_version($Name)) {
        $Cache{"get_CmdPath_Default"}{$Name} = $Name;
        return $Name;
    }
    if($OSgroup eq "windows"
    and `$Name /? 2>$TMP_DIR/null`) {
        $Cache{"get_CmdPath_Default"}{$Name} = $Name;
        return $Name;
    }
    if($Name ne "which") {
        my $WhichCmd = get_CmdPath("which");
        if($WhichCmd and `$WhichCmd $Name 2>$TMP_DIR/null`)
        {
            $Cache{"get_CmdPath_Default"}{$Name} = $Name;
            return $Cache{"get_CmdPath_Default"}{$Name};
        }
    }
    foreach my $Path (sort {length($a)<=>length($b)} keys(%DefaultBinPaths))
    {
        if(-f $Path."/".$Name or -f $Path."/".$Name.".exe") {
            $Cache{"get_CmdPath_Default"}{$Name} = joinPath($Path,$Name);
            return $Cache{"get_CmdPath_Default"}{$Name};
        }
    }
    $Cache{"get_CmdPath_Default"}{$Name} = "";
    return "";
}

sub showPos($)
{
    my $Number = $_[0];
    if(not $Number) {
        $Number = 1;
    }
    else {
        $Number = int($Number)+1;
    }
    if($Number>3) {
        return $Number."th";
    }
    elsif($Number==1) {
        return "1st";
    }
    elsif($Number==2) {
        return "2nd";
    }
    elsif($Number==3) {
        return "3rd";
    }
    else {
        return $Number;
    }
}

sub getAR_EXT($)
{
    my $Target = $_[0];
    if(my $Ext = $OS_Archive{$Target}) {
        return $Ext;
    }
    return $OS_Archive{"default"};
}

sub readDescriptor($$)
{
    my ($LibVersion, $Content) = @_;
    return if(not $LibVersion);
    my $DName = $DumpAPI?"descriptor":"descriptor \"d$LibVersion\"";
    if(not $Content) {
        exitStatus("Error", "$DName is empty");
    }
    if($Content!~/\</) {
        exitStatus("Error", "descriptor should be one of the following:\n  Java ARchive, XML descriptor, gzipped API dump or directory with Java ARchives.");
    }
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    $Descriptor{$LibVersion}{"Version"} = parseTag(\$Content, "version");
    $Descriptor{$LibVersion}{"Version"} = $TargetVersion{$LibVersion} if($TargetVersion{$LibVersion});
    if(not $Descriptor{$LibVersion}{"Version"}) {
        exitStatus("Error", "version in the $DName is not specified (<version> section)");
    }
    
    my $DArchives = parseTag(\$Content, "archives");
    if(not $DArchives){
        exitStatus("Error", "Java ARchives in the $DName are not specified (<archive> section)");
    }
    else
    {# append the descriptor Java ARchives list
        if($Descriptor{$LibVersion}{"Archives"}) {
            $Descriptor{$LibVersion}{"Archives"} .= "\n".$DArchives;
        }
        else {
            $Descriptor{$LibVersion}{"Archives"} = $DArchives;
        }
        foreach my $Path (split(/\s*\n\s*/, $DArchives))
        {
            if(not -e $Path) {
                exitStatus("Access_Error", "can't access \'$Path\'");
            }
        }
    }
    foreach my $Package (split(/\s*\n\s*/, parseTag(\$Content, "skip_packages"))) {
        $SkipPackages{$LibVersion}{$Package} = 1;
    }
    foreach my $Package (split(/\s*\n\s*/, parseTag(\$Content, "packages"))) {
        $KeepPackages{$LibVersion}{$Package} = 1;
    }
}

sub parseTag($$)
{
    my ($CodeRef, $Tag) = @_;
    return "" if(not $CodeRef or not ${$CodeRef} or not $Tag);
    if(${$CodeRef}=~s/\<\Q$Tag\E\>((.|\n)+?)\<\/\Q$Tag\E\>//)
    {
        my $Content = $1;
        $Content=~s/(\A\s+|\s+\Z)//g;
        return $Content;
    }
    else
    {
        return "";
    }
}

sub ignore_path($$)
{
    my ($Path, $Prefix) = @_;
    return 1 if(not $Path or not -e $Path
    or not $Prefix or not -e $Prefix);
    return 1 if($Path=~/\~\Z/);# skipping system backup files
    # skipping hidden .svn, .git, .bzr, .hg and CVS directories
    return 1 if(cut_path_prefix($Path, $Prefix)=~/(\A|[\/\\]+)(\.(svn|git|bzr|hg)|CVS)([\/\\]+|\Z)/);
    return 0;
}

sub cut_path_prefix($$)
{
    my ($Path, $Prefix) = @_;
    $Prefix=~s/[\/\\]+\Z//;
    $Path=~s/\A\Q$Prefix\E([\/\\]+|\Z)//;
    return $Path;
}

sub get_filename($)
{# much faster than basename() from File::Basename module
    return $Cache{"get_filename"}{$_[0]} if($Cache{"get_filename"}{$_[0]});
    if($_[0]=~/([^\/\\]+)\Z/) {
        return ($Cache{"get_filename"}{$_[0]} = $1);
    }
    return "";
}

sub get_dirname($)
{# much faster than dirname() from File::Basename module
    if($_[0]=~/\A(.*)[\/\\]+([^\/\\]*)\Z/) {
        return $1;
    }
    return "";
}

sub separate_path($)
{
    return (get_dirname($_[0]), get_filename($_[0]));
}

sub esc($)
{
    my $Str = $_[0];
    $Str=~s/([()\[\]{}$ &'"`;,<>\+])/\\$1/g;
    return $Str;
}

sub get_Signature($$$)
{
    my ($Method, $LibVersion, $Kind) = @_;
    if(defined $Cache{"get_Signature"}{$LibVersion}{$Method}{$Kind}) {
        return $Cache{"get_Signature"}{$LibVersion}{$Method}{$Kind};
    }
    my $Signature = $MethodInfo{$LibVersion}{$Method}{"ShortName"};
    if($Kind eq "Full") {
        $Signature = get_TypeName($MethodInfo{$LibVersion}{$Method}{"Class"}, $LibVersion).".".$Signature;
    }
    my @Params = ();
    foreach my $PPos (sort {int($a)<=>int($b)}
    keys(%{$MethodInfo{$LibVersion}{$Method}{"Param"}}))
    {
        my $PTid = $MethodInfo{$LibVersion}{$Method}{"Param"}{$PPos}{"Type"};
        if(my $PTName = get_TypeName($PTid, $LibVersion))
        {
            if($Kind eq "Full")
            {
                my $PName = $MethodInfo{$LibVersion}{$Method}{"Param"}{$PPos}{"Name"};
                push(@Params, $PTName." ".$PName);
            }
            else {
                push(@Params, $PTName);
            }
        }
    }
    $Signature .= "(".join(", ", @Params).")";
    if($Kind eq "Full")
    {
        if($MethodInfo{$LibVersion}{$Method}{"Static"}) {
            $Signature .= " [static]";
        }
        elsif($MethodInfo{$LibVersion}{$Method}{"Abstract"}) {
            $Signature .= " [abstract]";
        }
        if(my $ReturnId = $MethodInfo{$LibVersion}{$Method}{"Return"}) {
            $Signature .= " :".get_TypeName($ReturnId, $LibVersion);
        }
        $Signature=~s/java\.lang\.//g;
    }
    $Cache{"get_Signature"}{$LibVersion}{$Method}{$Kind} = $Signature;
    return $Cache{"get_Signature"}{$LibVersion}{$Method}{$Kind};
}

sub joinPath($$)
{
    return join($SLASH, @_);
}

sub get_filter_cmd($$)
{
    my ($Path, $Filter) = @_;
    if($OSgroup eq "windows") {
        return "type $Path | find \"$Filter\"";
    }
    else {
        return "cat $Path | grep \"$Filter\"";
    }
}

sub get_abs_path($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them
    my $Path = $_[0];
    if(not is_abs($Path)) {
        $Path = abs_path($Path);
    }
    return $Path;
}

sub is_abs($) {
    return ($_[0]=~/\A(\/|\w+:[\/\\])/);
}

sub cmd_find($$$$)
{
    my ($Path, $Type, $Name, $MaxDepth) = @_;
    return () if(not $Path or not -e $Path);
    if($OSgroup eq "windows")
    {
        my $DirCmd = get_CmdPath("dir");
        if(not $DirCmd) {
            exitStatus("Not_Found", "can't find \"dir\" command");
        }
        $Path=~s/[\\]+\Z//;
        $Path = get_abs_path($Path);
        my $Cmd = $DirCmd." \"$Path\" /B /O";
        if($MaxDepth!=1) {
            $Cmd .= " /S";
        }
        if($Type eq "d") {
            $Cmd .= " /AD";
        }
        my @Files = ();
        if($Name)
        { # FIXME: how to search file names in MS shell?
            $Name=~s/\*/.*/g if($Name!~/\]/);
            foreach my $File (split(/\n/, `$Cmd`))
            {
                if($File=~/$Name\Z/i) {
                    push(@Files, $File);    
                }
            }
        }
        else {
            @Files = split(/\n/, `$Cmd 2>$TMP_DIR/null`);
        }
        my @AbsPaths = ();
        foreach my $File (@Files)
        {
            if(not is_abs($File)) {
                $File = joinPath($Path, $File);
            }
            if($Type eq "f" and not -f $File)
            { # skip dirs
                next;
            }
            push(@AbsPaths, $File);
        }
        if($Type eq "d") {
            push(@AbsPaths, $Path);
        }
        return @AbsPaths;
    }
    else
    {
        my $FindCmd = get_CmdPath("find");
        if(not $FindCmd) {
            exitStatus("Not_Found", "can't find a \"find\" command");
        }
        $Path = get_abs_path($Path);
        if(-d $Path and -l $Path
        and $Path!~/\/\Z/)
        { # for directories that are symlinks
            $Path.="/";
        }
        my $Cmd = $FindCmd." \"$Path\"";
        if($MaxDepth) {
            $Cmd .= " -maxdepth $MaxDepth";
        }
        if($Type) {
            $Cmd .= " -type $Type";
        }
        if($Name)
        {
            if($Name=~/\]/) {
                $Cmd .= " -regex \"$Name\"";
            }
            else {
                $Cmd .= " -name \"$Name\"";
            }
        }
        return split(/\n/, `$Cmd 2>$TMP_DIR/null`);
    }
}

sub path_format($$)
{ # forward slash to pass into MinGW GCC
    my ($Path, $Fmt) = @_;
    if($Fmt eq "windows")
    {
        $Path=~s/\//\\/g;
        $Path=lc($Path);
    }
    else {
        $Path=~s/\\/\//g;
    }
    return $Path;
}

sub unpackDump($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -e $Path);
    $Path = get_abs_path($Path);
    $Path = path_format($Path, $OSgroup);
    my ($Dir, $FileName) = separate_path($Path);
    my $UnpackDir = $TMP_DIR."/unpack";
    rmtree($UnpackDir);
    mkpath($UnpackDir);
    if($FileName=~s/\Q.zip\E\Z//g)
    { # *.zip
        my $UnzipCmd = get_CmdPath("unzip");
        if(not $UnzipCmd) {
            exitStatus("Not_Found", "can't find \"unzip\" command");
        }
        chdir($UnpackDir);
        system("$UnzipCmd \"$Path\" >$UnpackDir/contents.txt");
        if($?) {
            exitStatus("Error", "can't extract \'$Path\'");
        }
        chdir($ORIG_DIR);
        my @Contents = ();
        foreach (split("\n", readFile("$UnpackDir/contents.txt")))
        {
            if(/inflating:\s*([^\s]+)/) {
                push(@Contents, $1);
            }
        }
        if(not @Contents) {
            exitStatus("Error", "can't extract \'$Path\'");
        }
        return joinPath($UnpackDir, $Contents[0]);
    }
    elsif($FileName=~s/\Q.tar.gz\E\Z//g)
    { # *.tar.gz
        if($OSgroup eq "windows")
        { # -xvzf option is not implemented in tar.exe (2003)
          # use "gzip.exe -k -d -f" + "tar.exe -xvf" instead
            my $TarCmd = get_CmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            my $GzipCmd = get_CmdPath("gzip");
            if(not $GzipCmd) {
                exitStatus("Not_Found", "can't find \"gzip\" command");
            }
            chdir($UnpackDir);
            system("$GzipCmd -k -d -f \"$Path\"");# keep input files (-k)
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            system("$TarCmd -xvf \"$Dir\\$FileName.tar\" >$UnpackDir/contents.txt");
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            chdir($ORIG_DIR);
            unlink($Dir."/".$FileName.".tar");
            my @Contents = split("\n", readFile("$UnpackDir/contents.txt"));
            if(not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            return joinPath($UnpackDir, $Contents[0]);
        }
        else
        { # Unix
            my $TarCmd = get_CmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            chdir($UnpackDir);
            system("$TarCmd -xvzf \"$Path\" >$UnpackDir/contents.txt");
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            chdir($ORIG_DIR);
            # The content file name may be different
            # from the package file name
            my @Contents = split("\n", readFile("$UnpackDir/contents.txt"));
            if(not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            return joinPath($UnpackDir, $Contents[0]);
        }
    }
}

sub mergeClasses()
{
    foreach my $ClassName (keys(%{$Class_Methods{1}}))
    {
        next if(not $ClassName);
        my $Type1_Id = $TName_Tid{1}{$ClassName};
        my %Type1 = get_Type($Type1_Id, 1);
        if(defined $Type1{"Access"}
        and $Type1{"Access"}=~/private/) {
            next;
        }
        my $Type2_Id = $TName_Tid{2}{$ClassName};
        if(not $Type2_Id)
        {
            foreach my $Method (keys(%{$Class_Methods{1}{$ClassName}}))
            { # removed classes/interfaces with public methods
                next if(not methodFilter($Method, 1));
                $CheckedTypes{$ClassName} = 1;
                $CheckedMethods{$Method} = 1;
                if($Type1{"Type"} eq "class")
                {
                    %{$CompatProblems{$Method}{"Removed_Class"}{"this"}} = (
                        "Type_Name"=>$ClassName,
                        "Target"=>$ClassName  );
                }
                else
                {
                    %{$CompatProblems{$Method}{"Removed_Interface"}{"this"}} = (
                        "Type_Name"=>$ClassName,
                        "Target"=>$ClassName  );
                }
            }
        }
    }
}

sub findFieldPair($$)
{
    my ($Field_Pos, $Pair_Type) = @_;
    foreach my $Pair_Name (keys(%{$Pair_Type->{"Fields"}}))
    {
        if(defined $Pair_Type->{"Fields"}{$Pair_Name})
        {
            if($Pair_Type->{"Fields"}{$Pair_Name}{"Pos"} eq $Field_Pos) {
                return $Pair_Name;
            }
        }
    }
    return "lost";
}

my %Severity_Val=(
    "High"=>3,
    "Medium"=>2,
    "Low"=>1,
    "Safe"=>-1
);

sub maxSeverity($$)
{
    my ($S1, $S2) = @_;
    if(cmpSeverities($S1, $S2)) {
        return $S1;
    }
    else {
        return $S2;
    }
}

sub cmpSeverities($$)
{
    my ($S1, $S2) = @_;
    if(not $S1) {
        return 0;
    }
    elsif(not $S2) {
        return 1;
    }
    return ($Severity_Val{$S1}>$Severity_Val{$S2});
}

sub getProblemSeverity($$$$)
{
    my ($Level, $Kind, $TypeName, $Target) = @_;
    if($Level eq "Source")
    {
        if($TypeProblems_Kind{$Level}{$Kind}) {
            return $TypeProblems_Kind{$Level}{$Kind};
        }
        elsif($MethodProblems_Kind{$Level}{$Kind}) {
            return $MethodProblems_Kind{$Level}{$Kind};
        }
    }
    elsif($Level eq "Binary")
    {
        if($Kind eq "Interface_Added_Abstract_Method"
        or $Kind eq "Abstract_Class_Added_Abstract_Method")
        {
            if(not keys(%{$MethodInvoked{2}{$Target}}))
            {
                if($Quick) {
                    return "Low";
                }
                else {
                    return "Safe";
                }
            }
        }
        elsif($Kind eq "Interface_Added_Super_Interface"
        or $Kind eq "Abstract_Class_Added_Super_Interface"
        or $Kind eq "Abstract_Class_Added_Super_Abstract_Class")
        {
            if(not keys(%{$ClassMethod_AddedInvoked{$TypeName}}))
            {
                if($Quick) {
                    return "Low";
                }
                else {
                    return "Safe";
                }
            }
        }
        elsif($Kind eq "Changed_Final_Field_Value")
        {
            if($Target=~/(\A|_)(VERSION|VERNUM)(_|\Z)/i) {
                return "Low";
            }
        }
        if($TypeProblems_Kind{$Level}{$Kind}) {
            return $TypeProblems_Kind{$Level}{$Kind};
        }
        elsif($MethodProblems_Kind{$Level}{$Kind}) {
            return $MethodProblems_Kind{$Level}{$Kind};
        }
    }
    return "Low";
}

sub isRecurType($$)
{
    foreach (@RecurTypes)
    {
        if($_->{"Tid1"} eq $_[0]
        and $_->{"Tid2"} eq $_[1])
        {
            return 1;
        }
    }
    return 0;
}

sub pushType($$)
{
    my %TypeDescriptor=(
        "Tid1"  => $_[0],
        "Tid2"  => $_[1]  );
    push(@RecurTypes, \%TypeDescriptor);
}

sub get_SFormat($)
{
    my $Name = $_[0];
    $Name=~s/\./\//g;
    return $Name;
}

sub get_PFormat($)
{
    my $Name = $_[0];
    $Name=~s/\//./g;
    return $Name;
}

sub get_ConstantValue($$)
{
    my ($Value, $ValueType) = @_;
    return "" if(not $Value);
    if($Value eq "\@EMPTY_STRING\@") {
        return "\"\"";
    }
    elsif($ValueType eq "java.lang.String") {
        return "\"".$Value."\"";
    }
    else {
        return $Value;
    }
}

sub mergeTypes($$)
{
    my ($Type1_Id, $Type2_Id) = @_;
    return () if(not $Type1_Id or not $Type2_Id);
    my (%Sub_SubProblems, %SubProblems) = ();
    return %{$Cache{"mergeTypes"}{$Type1_Id}{$Type2_Id}} if($Cache{"mergeTypes"}{$Type1_Id}{$Type2_Id});
    my %Type1 = get_Type($Type1_Id, 1);
    my %Type2 = get_Type($Type2_Id, 2);
    if(isRecurType($Type1_Id, $Type2_Id))
    { # do not follow to recursive declarations
        return ();
    }
    return () if(not $Type1{"Name"} or not $Type2{"Name"});
    return () if(not $Type1{"Archive"} or not $Type2{"Archive"});
    return () if($Type1{"Name"} ne $Type2{"Name"});
    return () if(skip_package($Type1{"Package"}, 1));
    $CheckedTypes{$Type1{"Name"}} = 1;
    if($Type1{"BaseType"} and $Type2{"BaseType"})
    { # check base type (arrays)
        return mergeTypes($Type1{"BaseType"}, $Type2{"BaseType"});
    }
    return () if($Type2{"Type"}!~/(class|interface)/);
    if($Type1{"Type"} eq "class" and not $Class_Constructed{1}{$Type1_Id})
    { # class cannot be constructed or inherited by clients
        return ();
    }
    if($Type1{"Type"} eq "class"
    and $Type2{"Type"} eq "interface")
    {
        %{$SubProblems{"Class_Became_Interface"}{""}}=(
            "Type_Name"=>$Type1{"Name"}  );
        %{$Cache{"mergeTypes"}{$Type1_Id}{$Type2_Id}} = %SubProblems;
        pop(@RecurTypes);
        return %SubProblems;
    }
    if($Type1{"Type"} eq "interface"
    and $Type2{"Type"} eq "class")
    {
        %{$SubProblems{"Interface_Became_Class"}{""}}=(
            "Type_Name"=>$Type1{"Name"}  );
        %{$Cache{"mergeTypes"}{$Type1_Id}{$Type2_Id}} = %SubProblems;
        pop(@RecurTypes);
        return %SubProblems;
    }
    if(not $Type1{"Final"}
    and $Type2{"Final"})
    {
        %{$SubProblems{"Class_Became_Final"}{""}}=(
            "Type_Name"=>$Type1{"Name"},
            "Target"=>$Type1{"Name"}  );
    }
    if(not $Type1{"Abstract"}
    and $Type2{"Abstract"})
    {
        %{$SubProblems{"Class_Became_Abstract"}{""}}=(
            "Type_Name"=>$Type1{"Name"}  );
    }
    pushType($Type1_Id, $Type2_Id);
    foreach my $AddedMethod (keys(%{$AddedMethod_Abstract{$Type1{"Name"}}}))
    {
        if($Type1{"Type"} eq "class")
        {
            if($Type1{"Abstract"})
            {
                my $Add_Effect = "";
                if(my @InvokedBy = keys(%{$MethodInvoked{2}{$AddedMethod}}))
                {
                    my $MFirst = $InvokedBy[0];
                    $Add_Effect = " Added abstract method is called in 2nd library version by the method ".black_name($MethodInfo{1}{$MFirst}{"Signature"})." and may not be implemented by old clients.";
                }
                %{$SubProblems{"Abstract_Class_Added_Abstract_Method"}{get_SFormat($AddedMethod)}} = (
                    "Type_Name"=>$Type1{"Name"},
                    "Type_Type"=>$Type1{"Type"},
                    "Target"=>$AddedMethod,
                    "Add_Effect"=>$Add_Effect  );
            }
            else
            {
                %{$SubProblems{"NonAbstract_Class_Added_Abstract_Method"}{get_SFormat($AddedMethod)}} = (
                    "Type_Name"=>$Type1{"Name"},
                    "Type_Type"=>$Type1{"Type"},
                    "Target"=>$AddedMethod  );
            }
        }
        else
        {
            my $Add_Effect = "";
            if(my @InvokedBy = keys(%{$MethodInvoked{2}{$AddedMethod}}))
            {
                my $MFirst = $InvokedBy[0];
                $Add_Effect = " Added abstract method is called in 2nd library version by the method ".black_name($MethodInfo{1}{$MFirst}{"Signature"})." and may not be implemented by old clients.";
            }
            %{$SubProblems{"Interface_Added_Abstract_Method"}{get_SFormat($AddedMethod)}} = (
                "Type_Name"=>$Type1{"Name"},
                "Type_Type"=>$Type1{"Type"},
                "Target"=>$AddedMethod,
                "Add_Effect"=>$Add_Effect  );
        }
    }
    foreach my $RemovedMethod (keys(%{$RemovedMethod_Abstract{$Type1{"Name"}}}))
    {
        if($Type1{"Type"} eq "class")
        {
            %{$SubProblems{"Class_Removed_Abstract_Method"}{get_SFormat($RemovedMethod)}} = (
                "Type_Name"=>$Type1{"Name"},
                "Type_Type"=>$Type1{"Type"},
                "Target"=>$RemovedMethod  );
        }
        else
        {
            %{$SubProblems{"Interface_Removed_Abstract_Method"}{get_SFormat($RemovedMethod)}} = (
                "Type_Name"=>$Type1{"Name"},
                "Type_Type"=>$Type1{"Type"},
                "Target"=>$RemovedMethod  );
        }
    }
    if($Type1{"Type"} eq "class"
    and $Type2{"Type"} eq "class")
    {
        my %SuperClass1 = get_Type($Type1{"SuperClass"}, 1);
        my %SuperClass2 = get_Type($Type2{"SuperClass"}, 2);
        if($SuperClass2{"Name"} ne $SuperClass1{"Name"})
        {
            if($SuperClass1{"Name"} eq "java.lang.Object")
            {
                if($SuperClass2{"Abstract"}
                and $Type1{"Abstract"} and $Type2{"Abstract"}
                and keys(%{$Class_AbstractMethods{2}{$SuperClass2{"Name"}}}))
                {
                    my $Add_Effect = "";
                    if(my @Invoked = keys(%{$ClassMethod_AddedInvoked{$Type1{"Name"}}}))
                    {
                        my $MFirst = $Invoked[0];
                        my $MSignature = unmangle($MFirst);
                        $MSignature=~s/\A.+\.(\w+\()/$1/g; # short name
                        my $InvokedBy = $ClassMethod_AddedInvoked{$Type1{"Name"}}{$MFirst};
                        $Add_Effect = " Abstract method ".black_name($MSignature)." from the added abstract super-class is called by the method ".black_name($MethodInfo{2}{$InvokedBy}{"Signature"})." in 2nd library version and may not be implemented by old clients.";
                    }
                    %{$SubProblems{"Abstract_Class_Added_Super_Abstract_Class"}{""}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Target"=>$SuperClass2{"Name"},
                        "Add_Effect"=>$Add_Effect  );
                }
                else
                {
                    %{$SubProblems{"Added_Super_Class"}{""}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Target"=>$SuperClass2{"Name"}  );
                }
            }
            elsif($SuperClass2{"Name"} eq "java.lang.Object")
            {
                %{$SubProblems{"Removed_Super_Class"}{""}} = (
                    "Type_Name"=>$Type1{"Name"},
                    "Target"=>$SuperClass1{"Name"}  );
            }
            else
            {
                %{$SubProblems{"Changed_Super_Class"}{""}} = (
                    "Type_Name"=>$Type1{"Name"},
                    "Target"=>$SuperClass1{"Name"},
                    "Old_Value"=>$SuperClass1{"Name"},
                    "New_Value"=>$SuperClass2{"Name"}  );
            }
        }
    }
    my %SuperInterfaces_Old = map {get_TypeName($_, 1) => 1} keys(%{$Type1{"SuperInterface"}});
    my %SuperInterfaces_New = map {get_TypeName($_, 2) => 1} keys(%{$Type2{"SuperInterface"}});
    foreach my $SuperInterface (keys(%SuperInterfaces_New))
    {
        if(not $SuperInterfaces_Old{$SuperInterface})
        {
            if($Type1{"Type"} eq "interface")
            {
                if(keys(%{$Class_AbstractMethods{2}{$SuperInterface}})
                or $SuperInterface=~/\Ajava\./)
                {
                    my $Add_Effect = "";
                    if(my @Invoked = keys(%{$ClassMethod_AddedInvoked{$Type1{"Name"}}}))
                    {
                        my $MFirst = $Invoked[0];
                        my $MSignature = unmangle($MFirst);
                        $MSignature=~s/\A.+\.(\w+\()/$1/g; # short name
                        my $InvokedBy = $ClassMethod_AddedInvoked{$Type1{"Name"}}{$MFirst};
                        $Add_Effect = " Abstract method ".black_name($MSignature)." from the added super-interface is called by the method ".black_name($MethodInfo{2}{$InvokedBy}{"Signature"})." in 2nd library version and may not be implemented by old clients.";
                    }
                    %{$SubProblems{"Interface_Added_Super_Interface"}{get_SFormat($SuperInterface)}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Target"=>$SuperInterface,
                        "Add_Effect"=>$Add_Effect  );
                }
                elsif(keys(%{$Class_Fields{2}{$SuperInterface}}))
                {
                    %{$SubProblems{"Interface_Added_Super_Constant_Interface"}{get_SFormat($SuperInterface)}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Target"=>$SuperInterface  );
                }
                else {
                    # ???
                }
            }
            else
            {
                if($Type1{"Abstract"} and $Type2{"Abstract"})
                {
                    my $Add_Effect = "";
                    if(my @Invoked = keys(%{$ClassMethod_AddedInvoked{$Type1{"Name"}}}))
                    {
                        my $MFirst = $Invoked[0];
                        my $MSignature = unmangle($MFirst);
                        $MSignature=~s/\A.+\.(\w+\()/$1/g; # short name
                        my $InvokedBy = $ClassMethod_AddedInvoked{$Type1{"Name"}}{$MFirst};
                        $Add_Effect = " Abstract method ".black_name($MSignature)." from the added super-interface is called by the method ".black_name($MethodInfo{2}{$InvokedBy}{"Signature"})." in 2nd library version and may not be implemented by old clients.";
                    }
                    %{$SubProblems{"Abstract_Class_Added_Super_Interface"}{get_SFormat($SuperInterface)}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Target"=>$SuperInterface,
                        "Add_Effect"=>$Add_Effect  );
                }
            }
        }
    }
    foreach my $SuperInterface (keys(%SuperInterfaces_Old))
    {
        if(not $SuperInterfaces_New{$SuperInterface}) {
            if($Type1{"Type"} eq "interface")
            {
                if(keys(%{$Class_AbstractMethods{1}{$SuperInterface}})
                or $SuperInterface=~/\Ajava\./)
                {
                    %{$SubProblems{"Interface_Removed_Super_Interface"}{get_SFormat($SuperInterface)}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Type_Type"=>"interface",
                        "Target"=>$SuperInterface  );
                }
                elsif(keys(%{$Class_Fields{1}{$SuperInterface}}))
                {
                    %{$SubProblems{"Interface_Removed_Super_Constant_Interface"}{get_SFormat($SuperInterface)}} = (
                        "Type_Name"=>$Type1{"Name"},
                        "Target"=>$SuperInterface  );
                }
                else {
                    # ???
                }
            }
            else
            {
                %{$SubProblems{"Class_Removed_Super_Interface"}{get_SFormat($SuperInterface)}} = (
                    "Type_Name"=>$Type1{"Name"},
                    "Type_Type"=>"class",
                    "Target"=>$SuperInterface  );
            }
        }
    }
    foreach my $Field_Name (keys(%{$Type1{"Fields"}}))
    {# check older fields
        my $Access1 = $Type1{"Fields"}{$Field_Name}{"Access"};
        next if($Access1=~/private/);
        my $Field_Pos1 = $Type1{"Fields"}{$Field_Name}{"Pos"};
        my $FieldType1_Id = $Type1{"Fields"}{$Field_Name}{"Type"};
        my %FieldType1 = get_Type($FieldType1_Id, 1);
        if(not $Type2{"Fields"}{$Field_Name})
        {# removed fields
            my $StraightPair_Name = findFieldPair($Field_Pos1, \%Type2);
            if($StraightPair_Name ne "lost" and not $Type1{"Fields"}{$StraightPair_Name}
            and $FieldType1{"Name"} eq get_TypeName($Type2{"Fields"}{$StraightPair_Name}{"Type"}, 2))
            {
                if(my $Constant = get_ConstantValue($Type1{"Fields"}{$Field_Name}{"Value"}, $FieldType1{"Name"}))
                {
                    %{$SubProblems{"Renamed_Constant_Field"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Type_Name"=>$Type1{"Name"},
                        "Old_Value"=>$Field_Name,
                        "New_Value"=>$StraightPair_Name,
                        "Field_Type"=>$FieldType1{"Name"},
                        "Field_Value"=>$Constant  );
                }
                else
                {
                    %{$SubProblems{"Renamed_Field"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Type_Name"=>$Type1{"Name"},
                        "Old_Value"=>$Field_Name,
                        "New_Value"=>$StraightPair_Name,
                        "Field_Type"=>$FieldType1{"Name"}  );
                }
            }
            else
            {
                if(my $Constant = get_ConstantValue($Type1{"Fields"}{$Field_Name}{"Value"}, $FieldType1{"Name"}))
                { # has a compile-time constant value
                    %{$SubProblems{"Removed_Constant_Field"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Type_Name"=>$Type1{"Name"},
                        "Field_Value"=>$Constant,
                        "Field_Type"=>$FieldType1{"Name"},
                        "Type_Type"=>$Type1{"Type"}  );
                }
                else
                {
                    %{$SubProblems{"Removed_NonConstant_Field"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Type_Name"=>$Type1{"Name"},
                        "Type_Type"=>$Type1{"Type"},
                        "Field_Type"=>$FieldType1{"Name"}  );
                }
            }
            next;
        }
        my $FieldType2_Id = $Type2{"Fields"}{$Field_Name}{"Type"};
        my %FieldType2 = get_Type($FieldType2_Id, 2);
        
        if(not $Type1{"Fields"}{$Field_Name}{"Static"}
        and $Type2{"Fields"}{$Field_Name}{"Static"})
        {
            if(not $Type1{"Fields"}{$Field_Name}{"Value"})
            {
                %{$SubProblems{"NonConstant_Field_Became_Static"}{$Field_Name}}=(
                    "Target"=>$Field_Name,
                    "Field_Type"=>$FieldType1{"Name"},
                    "Type_Name"=>$Type1{"Name"}  );
            }
        }
        elsif($Type1{"Fields"}{$Field_Name}{"Static"}
        and not $Type2{"Fields"}{$Field_Name}{"Static"})
        {
            if($Type1{"Fields"}{$Field_Name}{"Value"})
            {
                %{$SubProblems{"Constant_Field_Became_NonStatic"}{$Field_Name}}=(
                    "Target"=>$Field_Name,
                    "Field_Type"=>$FieldType1{"Name"},
                    "Type_Name"=>$Type1{"Name"}  );
            }
            else
            {
                %{$SubProblems{"NonConstant_Field_Became_NonStatic"}{$Field_Name}}=(
                    "Target"=>$Field_Name,
                    "Field_Type"=>$FieldType1{"Name"},
                    "Type_Name"=>$Type1{"Name"}  );
            }
        }
        if(not $Type1{"Fields"}{$Field_Name}{"Final"}
        and $Type2{"Fields"}{$Field_Name}{"Final"})
        {
            %{$SubProblems{"Field_Became_Final"}{$Field_Name}}=(
                "Target"=>$Field_Name,
                "Field_Type"=>$FieldType1{"Name"},
                "Type_Name"=>$Type1{"Name"}  );
        }
        elsif($Type1{"Fields"}{$Field_Name}{"Final"}
        and not $Type2{"Fields"}{$Field_Name}{"Final"})
        {
            %{$SubProblems{"Field_Became_NonFinal"}{$Field_Name}}=(
                "Target"=>$Field_Name,
                "Field_Type"=>$FieldType1{"Name"},
                "Type_Name"=>$Type1{"Name"}  );
        }
        my $Access2 = $Type2{"Fields"}{$Field_Name}{"Access"};
        if($Access1 eq "public" and $Access2=~/protected|private/
        or $Access1 eq "protected" and $Access2=~/private/)
        {
            %{$SubProblems{"Changed_Field_Access"}{$Field_Name}}=(
                "Target"=>$Field_Name,
                "Type_Name"=>$Type1{"Name"},
                "Old_Value"=>$Access1,
                "New_Value"=>$Access2  );
        }
        my $Value1 = get_ConstantValue($Type1{"Fields"}{$Field_Name}{"Value"}, $FieldType1{"Name"});
        my $Value2 = get_ConstantValue($Type2{"Fields"}{$Field_Name}{"Value"}, $FieldType2{"Name"});
        if($Value1 ne $Value2)
        {
            if($Value1 and $Value2)
            {
                if($Type1{"Fields"}{$Field_Name}{"Final"}
                and $Type2{"Fields"}{$Field_Name}{"Final"})
                {
                    %{$SubProblems{"Changed_Final_Field_Value"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Field_Type"=>$FieldType1{"Name"},
                        "Type_Name"=>$Type1{"Name"},
                        "Old_Value"=>$Value1,
                        "New_Value"=>$Value2  );
                }
            }
        }
        %Sub_SubProblems = detectTypeChange($FieldType1_Id, $FieldType2_Id, "Field");
        foreach my $Sub_SubProblemType (keys(%Sub_SubProblems))
        {
            %{$SubProblems{$Sub_SubProblemType}{$Field_Name}}=(
                "Target"=>$Field_Name,
                "Type_Name"=>$Type1{"Name"}  );
            foreach my $Attr (keys(%{$Sub_SubProblems{$Sub_SubProblemType}}))
            {
                $SubProblems{$Sub_SubProblemType}{$Field_Name}{$Attr} = $Sub_SubProblems{$Sub_SubProblemType}{$Attr};
            }
        }
        if($FieldType1_Id and $FieldType2_Id)
        { # check field type change
            %Sub_SubProblems = mergeTypes($FieldType1_Id, $FieldType2_Id);
            foreach my $Sub_SubProblemType (keys(%Sub_SubProblems))
            {
                foreach my $Sub_SubLocation (keys(%{$Sub_SubProblems{$Sub_SubProblemType}}))
                {
                    my $NewLocation = ($Sub_SubLocation)?$Field_Name.".".$Sub_SubLocation:$Field_Name;
                    foreach my $Attr (keys(%{$Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}}))
                    {
                        $SubProblems{$Sub_SubProblemType}{$NewLocation}{$Attr} = $Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}{$Attr};
                    }
                    if($Sub_SubLocation!~/\./) {
                        $SubProblems{$Sub_SubProblemType}{$NewLocation}{"Start_Type_Name"} = $FieldType1{"Name"};
                    }
                }
            }
        }
    }
    foreach my $Field_Name (sort keys(%{$Type2{"Fields"}}))
    { # check added fields
        next if($Type2{"Fields"}{$Field_Name}{"Access"}=~/private/);
        my $FieldPos2 = $Type2{"Fields"}{$Field_Name}{"Pos"};
        my $FieldType2_Id = $Type2{"Fields"}{$Field_Name}{"Type"};
        my %FieldType2 = get_Type($FieldType2_Id, 2);
        if(not $Type1{"Fields"}{$Field_Name})
        {# added fields
            my $StraightPair_Name = findFieldPair($FieldPos2, \%Type1);
            if($StraightPair_Name ne "lost" and not $Type2{"Fields"}{$StraightPair_Name}
            and get_TypeName($Type1{"Fields"}{$StraightPair_Name}{"Type"}, 1) eq $FieldType2{"Name"})
            {
                # Already reported as "Renamed_Field" or "Renamed_Constant_Field"
            }
            else
            {
                if($Type1{"Type"} eq "interface")
                {
                    %{$SubProblems{"Interface_Added_Field"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Type_Name"=>$Type1{"Name"}  );
                }
                else
                {
                    %{$SubProblems{"Class_Added_Field"}{$Field_Name}}=(
                        "Target"=>$Field_Name,
                        "Type_Name"=>$Type1{"Name"}  );
                }
            }
        }
    }
    %{$Cache{"mergeTypes"}{$Type1_Id}{$Type2_Id}} = %SubProblems;
    pop(@RecurTypes);
    return %SubProblems;
}

sub unmangle($)
{
    my $Name = $_[0];
    $Name=~s!/!.!g;
    $Name=~s!:\(!(!g;
    $Name=~s!\).+\Z!)!g;
    if($Name=~/\A(.+)\((.+)\)/)
    {
        my ($ShortName, $MangledParams) = ($1, $2);
        my @UnmangledParams = ();
        my ($IsArray, $Shift, $Pos, $CurParam) = (0, 0, 0, "");
        while($Pos<length($MangledParams))
        {
            my $Symbol = substr($MangledParams, $Pos, 1);
            if($Symbol eq "[")
            { # array
                $IsArray = 1;
                $Pos+=1;
            }
            elsif($Symbol eq "L")
            { # class
                if(substr($MangledParams, $Pos+1)=~/\A(.+?);/) {
                    $CurParam = $1;
                    $Shift = length($CurParam)+2;
                }
                if($IsArray) {
                    $CurParam .= "[]";
                }
                $Pos+=$Shift;
                push(@UnmangledParams, $CurParam);
                ($IsArray, $Shift, $CurParam) = (0, 0, "")
            }
            else
            {
                if($Symbol eq "C") {
                    $CurParam = "char";
                }
                elsif($Symbol eq "B") {
                    $CurParam = "byte";
                }
                elsif($Symbol eq "S") {
                    $CurParam = "short";
                }
                elsif($Symbol eq "S") {
                    $CurParam = "short";
                }
                elsif($Symbol eq "I") {
                    $CurParam = "int";
                }
                elsif($Symbol eq "F") {
                    $CurParam = "float";
                }
                elsif($Symbol eq "J") {
                    $CurParam = "long";
                }
                elsif($Symbol eq "D") {
                    $CurParam = "double";
                }
                else {
                    print "WARNING: unmangling error\n";
                }
                if($IsArray) {
                    $CurParam .= "[]";
                }
                $Pos+=1;
                push(@UnmangledParams, $CurParam);
                ($IsArray, $Shift, $CurParam) = (0, 0, "")
            }
        }
        return $ShortName."(".join(", ", @UnmangledParams).")";
    }
    else {
        return $Name;
    }
}

sub black_name($)
{
    my $Name = $_[0];
    return "<span class='nblack'>".highLight_Signature($Name)."</span>";
}

sub get_TypeName($$)
{
    my ($TypeId, $LibVersion) = @_;
    return $TypeInfo{$LibVersion}{$TypeId}{"Name"};
}

sub get_ShortName($$)
{
    my ($TypeId, $LibVersion) = @_;
    my $TypeName = $TypeInfo{$LibVersion}{$TypeId}{"Name"};
    $TypeName=~s/\A.*\.//g;
    return $TypeName;
}

sub get_TypeType($$)
{
    my ($TypeId, $LibVersion) = @_;
    return $TypeInfo{$LibVersion}{$TypeId}{"Type"};
}

sub get_TypeHeader($$)
{
    my ($TypeId, $LibVersion) = @_;
    return $TypeInfo{$LibVersion}{$TypeId}{"Header"};
}

sub get_BaseType($$)
{
    my ($TypeId, $LibVersion) = @_;
    return "" if(not $TypeId);
    if(defined $Cache{"get_BaseType"}{$TypeId}{$LibVersion}) {
        return %{$Cache{"get_BaseType"}{$TypeId}{$LibVersion}};
    }
    return "" if(not $TypeInfo{$LibVersion}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeId}};
    return %Type if(not $Type{"BaseType"});
    %Type = get_BaseType($Type{"BaseType"}, $LibVersion);
    $Cache{"get_BaseType"}{$TypeId}{$LibVersion} = \%Type;
    return %Type;
}

sub get_OneStep_BaseType($$)
{
    my ($TypeId, $LibVersion) = @_;
    return "" if(not $TypeId);
    return "" if(not $TypeInfo{$LibVersion}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeId}};
    return %Type if(not $Type{"BaseType"});
    return get_Type($Type{"BaseType"}, $LibVersion);
}

sub get_Type($$)
{
    my ($TypeId, $LibVersion) = @_;
    return "" if(not $TypeId);
    return "" if(not $TypeInfo{$LibVersion}{$TypeId});
    return %{$TypeInfo{$LibVersion}{$TypeId}};
}

sub methodFilter($$)
{
    my ($Method, $LibVersion) = @_;
    if($ClassListPath and defined $MethodInfo{$LibVersion}{$Method}
    and not $ClassList_User{$MethodInfo{$LibVersion}{$Method}{"Class"}})
    { # user defined classes
        return 0;
    }
    if($ClientPath and not $UsedMethods_Client{$Method})
    { # user defined application
        return 0;
    }
    if(skip_package($MethodInfo{$LibVersion}{$Method}{"Package"}, $LibVersion))
    { # internal packages
        return 0;
    }
    return 1;
}

sub skip_package($$)
{
    my ($Package, $LibVersion) = @_;
    return 0 if(not $Package);
    if(not $KeepInternal)
    {
        if($Package=~/\A(com\.oracle|com\.sun|COM\.rsa|sun|sunw)/)
        { # private packages
          # http://java.sun.com/products/jdk/faq/faq-sun-packages.html
            return 1;
        }
        if($Package=~/(\A|\.)(internal|impl|examples)(\.|\Z)/)
        { # internal packages
            return 1;
        }
    }
    foreach my $SkipPackage (keys(%{$SkipPackages{$LibVersion}}))
    {
        if($Package=~/(\A|\.)\Q$SkipPackage\E(\.|\Z)/)
        { # user skipped packages
            return 1;
        }
    }
    if(my @Keeped = keys(%{$KeepPackages{$LibVersion}}))
    {
        my $UserKeeped = 0;
        foreach my $KeepPackage (@Keeped)
        {
            if($Package=~/(\A|\.)\Q$KeepPackage\E(\.|\Z)/)
            { # user keeped packages
                $UserKeeped = 1;
            }
        }
        if(not $UserKeeped) {
            return 1;
        }
    }
    return 0;
}

sub mergeImplementations()
{
    my $DiffCmd = get_CmdPath("diff");
    if(not $DiffCmd) {
        exitStatus("Not_Found", "can't find \"diff\" command");
    }
    foreach my $Method (sort keys(%{$MethodInfo{1}}))
    { # implementation changes
        next if($MethodInfo{1}{$Method}{"Access"}=~/private/);
        next if(not defined $MethodInfo{2}{$Method});
        next if(not methodFilter($Method, 1));
        my $Impl1 = canonifyCode($MethodBody{1}{$Method});
        next if(not $Impl1);
        my $Impl2 = canonifyCode($MethodBody{2}{$Method});
        next if(not $Impl2);
        if($Impl1 ne $Impl2)
        {
            writeFile("$TMP_DIR/impl1", $Impl1);
            writeFile("$TMP_DIR/impl2", $Impl2);
            my $Diff = `$DiffCmd -rNau $TMP_DIR/impl1 $TMP_DIR/impl2`;
            $Diff=~s/(---|\+\+\+).+\n//g;
            $Diff=~s/\n\@\@/\n \n\@\@/g;
            unlink("$TMP_DIR/impl1", "$TMP_DIR/impl2");
            %{$ImplProblems{$Method}}=(
                "Diff" => get_CodeView($Diff) );
        }
    }
}

sub canonifyCode($)
{
    my $MethodBody = $_[0];
    return "" if(not $MethodBody);
    $MethodBody=~s/#\d+; //g;
    return $MethodBody;
}

sub get_CodeView($)
{
    my $Code = $_[0];
    my $View = "";
    foreach my $Line (split(/\n/, $Code))
    {
        if($Line=~s/\A(\+|-)/$1 /g) {
            $Line = "<b>".htmlSpecChars($Line)."</b>";
        }
        else {
            $Line = "<span style='padding-left:8px;'>".htmlSpecChars($Line)."</span>";
        }
        $View .= "<tr><td class='code_line'>$Line</td></tr>\n";
    }
    return "<table class='code_view'>$View</table>\n";
}

sub get_MSuffix($)
{
    my $Method = $_[0];
    if($Method=~/(\(.*\))/) {
        return $1;
    }
    return "";
}

sub get_MShort($)
{
    my $Method = $_[0];
    if($Method=~/([^\.]+)\:\(/) {
        return $1;
    }
    return "";
}

sub findMethod($$$$)
{
    my ($Method, $MethodVersion, $ClassName, $ClassVersion) = @_;
    my $ClassId = $TName_Tid{$ClassVersion}{$ClassName};
    if(not $ClassId) {
        return "";
    }
    my @Search = ();
    if(get_TypeType($ClassId, $ClassVersion) eq "class")
    {
        if(my $SuperClassId = $TypeInfo{$ClassVersion}{$ClassId}{"SuperClass"}) {
            push(@Search, $SuperClassId);
        }
    }
    if(not defined $MethodInfo{$MethodVersion}{$Method}
    or $MethodInfo{$MethodVersion}{$Method}{"Abstract"})
    {
        if(my @SuperInterfaces = keys(%{$TypeInfo{$ClassVersion}{$ClassId}{"SuperInterface"}})) {
            push(@Search, @SuperInterfaces);
        }
    }
    foreach my $SuperId (@Search)
    {
        my $SuperName = get_TypeName($SuperId, $ClassVersion);
        if(my $MethodInClass = findMethod_Class($Method, $SuperName, $ClassVersion)) {
            return $MethodInClass;
        }
        elsif(my $MethodInSuperClasses = findMethod($Method, $MethodVersion, $SuperName, $ClassVersion)) {
            return $MethodInSuperClasses;
        }
    }
    return "";
}

sub findMethod_Class($$$)
{
    my ($Method, $ClassName, $ClassVersion) = @_;
    my $TargetSuffix = get_MSuffix($Method);
    my $TargetShortName = get_MShort($Method);
    foreach my $Candidate (keys(%{$Class_Methods{$ClassVersion}{$ClassName}}))
    {# search for method with the same parameters suffix
        next if($MethodInfo{$ClassVersion}{$Candidate}{"Constructor"});
        if($TargetSuffix eq get_MSuffix($Candidate))
        {
            if($TargetShortName eq get_MShort($Candidate)) {
                return $Candidate;
            }
        }
    }
    return "";
}

sub prepareMethods($)
{
    my $LibVersion = $_[0];
    foreach my $Method (keys(%{$MethodInfo{$LibVersion}}))
    {
        if($MethodInfo{$LibVersion}{$Method}{"Access"}!~/private/)
        {
            if($MethodInfo{$LibVersion}{$Method}{"Constructor"}) {
                registerUsage($MethodInfo{$LibVersion}{$Method}{"Class"}, $LibVersion);
            }
            else {
                registerUsage($MethodInfo{$LibVersion}{$Method}{"Return"}, $LibVersion);
            }
        }
    }
}

sub mergeMethods()
{
    my %SubProblems = ();
    foreach my $Method (sort keys(%{$MethodInfo{1}}))
    { # compare methods
        next if(not defined $MethodInfo{2}{$Method});
        if(not $MethodInfo{1}{$Method}{"Archive"}
        or not $MethodInfo{2}{$Method}{"Archive"}) {
            next;
        }
        if($MethodInfo{1}{$Method}{"Access"}=~/private/)
        { # skip private methods
            next;
        }
        next if(not methodFilter($Method, 1));
        $CheckedMethods{$Method}=1;
        my $ClassId1 = $MethodInfo{1}{$Method}{"Class"};
        my %Class1 = get_Type($ClassId1, 1);
        if($Class1{"Access"}=~/private/)
        {# skip private classes
            next;
        }
        my %Class2 = get_Type($MethodInfo{2}{$Method}{"Class"}, 2);
        if(not $MethodInfo{1}{$Method}{"Static"}
        and $Class1{"Type"} eq "class" and not $Class_Constructed{1}{$ClassId1})
        { # class cannot be constructed or inherited by clients
          # non-static method cannot be called
            next;
        }
        # checking attributes
        if(not $MethodInfo{1}{$Method}{"Static"}
        and $MethodInfo{2}{$Method}{"Static"}) {
            %{$CompatProblems{$Method}{"Method_Became_Static"}{""}} = ();
        }
        elsif($MethodInfo{1}{$Method}{"Static"}
        and not $MethodInfo{2}{$Method}{"Static"}) {
            %{$CompatProblems{$Method}{"Method_Became_NonStatic"}{""}} = ();
        }
        if(not $MethodInfo{1}{$Method}{"Synchronized"}
        and $MethodInfo{2}{$Method}{"Synchronized"}) {
            %{$CompatProblems{$Method}{"Method_Became_Synchronized"}{""}} = ();
        }
        elsif($MethodInfo{1}{$Method}{"Synchronized"}
        and not $MethodInfo{2}{$Method}{"Synchronized"}) {
            %{$CompatProblems{$Method}{"Method_Became_NonSynchronized"}{""}} = ();
        }
        if(not $MethodInfo{1}{$Method}{"Final"}
        and $MethodInfo{2}{$Method}{"Final"})
        {
            if($MethodInfo{1}{$Method}{"Static"}) {
                %{$CompatProblems{$Method}{"Static_Method_Became_Final"}{""}} = ();
            }
            else {
                %{$CompatProblems{$Method}{"NonStatic_Method_Became_Final"}{""}} = ();
            }
        }
        my $Access1 = $MethodInfo{1}{$Method}{"Access"};
        my $Access2 = $MethodInfo{2}{$Method}{"Access"};
        if($Access1 eq "public" and $Access2=~/protected|private/
        or $Access1 eq "protected" and $Access2=~/private/)
        {
            %{$CompatProblems{$Method}{"Changed_Method_Access"}{""}} = (
                "Old_Value"=>$Access1,
                "New_Value"=>$Access2  );
        }
        if($Class1{"Type"} eq "class"
        and $Class2{"Type"} eq "class")
        {
            if(not $MethodInfo{1}{$Method}{"Abstract"}
            and $MethodInfo{2}{$Method}{"Abstract"})
            {
                %{$CompatProblems{$Method}{"Method_Became_Abstract"}{""}} = ();
                %{$CompatProblems{$Method}{"Class_Method_Became_Abstract"}{get_SFormat($Method)}} = (
                    "Type_Name"=>$Class1{"Name"},
                    "Target"=>$Method  );
            }
            elsif($MethodInfo{1}{$Method}{"Abstract"}
            and not $MethodInfo{2}{$Method}{"Abstract"})
            {
                %{$CompatProblems{$Method}{"Method_Became_NonAbstract"}{""}} = ();
                %{$CompatProblems{$Method}{"Class_Method_Became_NonAbstract"}{get_SFormat($Method)}} = (
                    "Type_Name"=>$Class1{"Name"},
                    "Target"=>$Method  );
            }
        }
        my %Exceptions_Old = map {get_TypeName($_, 1) => $_} keys(%{$MethodInfo{1}{$Method}{"Exceptions"}});
        my %Exceptions_New = map {get_TypeName($_, 2) => $_} keys(%{$MethodInfo{2}{$Method}{"Exceptions"}});
        foreach my $Exception (keys(%Exceptions_Old))
        {
            if(not $Exceptions_New{$Exception})
            {
                my %ExceptionType = get_Type($Exceptions_Old{$Exception}, 1);
                my $SuperClass = $ExceptionType{"SuperClass"};
                if($KnownRuntimeExceptions{$Exception}
                or defined $SuperClass and get_TypeName($SuperClass, 1) eq "java.lang.RuntimeException")
                {
                    if(not $MethodInfo{1}{$Method}{"Abstract"}
                    and not $MethodInfo{2}{$Method}{"Abstract"})
                    {
                        %{$CompatProblems{$Method}{"Removed_Unchecked_Exception"}{get_SFormat($Exception)}} = (
                            "Type_Name"=>$Class1{"Name"},
                            "Target"=>$Exception  );
                    }
                }
                else
                {
                    if($MethodInfo{1}{$Method}{"Abstract"}
                    and $MethodInfo{2}{$Method}{"Abstract"})
                    {
                        %{$CompatProblems{$Method}{"Abstract_Method_Removed_Checked_Exception"}{get_SFormat($Exception)}} = (
                            "Type_Name"=>$Class1{"Name"},
                            "Target"=>$Exception  );
                    }
                    else
                    {
                        %{$CompatProblems{$Method}{"NonAbstract_Method_Removed_Checked_Exception"}{get_SFormat($Exception)}} = (
                            "Type_Name"=>$Class1{"Name"},
                            "Target"=>$Exception  );
                    }
                }
            }
        }
        foreach my $Exception (keys(%Exceptions_New))
        {
            if(not $Exceptions_Old{$Exception})
            {
                my %ExceptionType = get_Type($Exceptions_New{$Exception}, 2);
                my $SuperClass = $ExceptionType{"SuperClass"};
                if($KnownRuntimeExceptions{$Exception}
                or defined $SuperClass and get_TypeName($SuperClass, 2) eq "java.lang.RuntimeException")
                {
                    if(not $MethodInfo{1}{$Method}{"Abstract"}
                    and not $MethodInfo{2}{$Method}{"Abstract"})
                    {
                        %{$CompatProblems{$Method}{"Added_Unchecked_Exception"}{get_SFormat($Exception)}} = (
                            "Type_Name"=>$Class1{"Name"},
                            "Target"=>$Exception  );
                    }
                }
                else
                {
                    if($MethodInfo{1}{$Method}{"Abstract"}
                    and $MethodInfo{2}{$Method}{"Abstract"})
                    {
                        %{$CompatProblems{$Method}{"Abstract_Method_Added_Checked_Exception"}{get_SFormat($Exception)}} = (
                            "Type_Name"=>$Class1{"Name"},
                            "Target"=>$Exception  );
                    }
                    else
                    {
                        %{$CompatProblems{$Method}{"NonAbstract_Method_Added_Checked_Exception"}{get_SFormat($Exception)}} = (
                            "Type_Name"=>$Class1{"Name"},
                            "Target"=>$Exception  );
                    }
                }
            }
        }
        foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$MethodInfo{1}{$Method}{"Param"}}))
        {# checking parameters
            mergeParameters($Method, $ParamPos, $ParamPos);
        }
        # check object type
        my $ObjectType1_Id = $MethodInfo{1}{$Method}{"Class"};
        my $ObjectType2_Id = $MethodInfo{2}{$Method}{"Class"};
        if($ObjectType1_Id and $ObjectType2_Id)
        {
            @RecurTypes = ();
            %SubProblems = mergeTypes($ObjectType1_Id, $ObjectType2_Id);
            foreach my $SubProblemType (keys(%SubProblems))
            {
                foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                {
                    my $NewLocation = ($SubLocation)?"this.".$SubLocation:"this";
                    @{$CompatProblems{$Method}{$SubProblemType}{$NewLocation}}{keys(%{$SubProblems{$SubProblemType}{$SubLocation}})} = values %{$SubProblems{$SubProblemType}{$SubLocation}};
                    if($SubLocation!~/\./) {
                        $CompatProblems{$Method}{$SubProblemType}{$NewLocation}{"Start_Type_Name"} = get_TypeName($ObjectType1_Id, 1);
                    }
                }
            }
        }
        # check return type
        my $ReturnType1_Id = $MethodInfo{1}{$Method}{"Return"};
        my $ReturnType2_Id = $MethodInfo{2}{$Method}{"Return"};
        if($ReturnType1_Id and $ReturnType2_Id)
        {
            @RecurTypes = ();
            %SubProblems = mergeTypes($ReturnType1_Id, $ReturnType2_Id);
            foreach my $SubProblemType (keys(%SubProblems))
            {
                foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                {
                    my $NewLocation = ($SubLocation)?"RetVal.".$SubLocation:"RetVal";
                    @{$CompatProblems{$Method}{$SubProblemType}{$NewLocation}}{keys(%{$SubProblems{$SubProblemType}{$SubLocation}})} = values %{$SubProblems{$SubProblemType}{$SubLocation}};
                    if($SubLocation!~/\./) {
                        $CompatProblems{$Method}{$SubProblemType}{$NewLocation}{"Start_Type_Name"} = get_TypeName($ReturnType1_Id, 1);
                    }
                }
            }
        }
    }
}

sub mergeParameters($$$)
{
    my ($Method, $ParamPos1, $ParamPos2) = @_;
    return if(not $Method or not defined $MethodInfo{1}{$Method}{"Param"}
    or not defined $MethodInfo{2}{$Method}{"Param"});
    my $ParamType1_Id = $MethodInfo{1}{$Method}{"Param"}{$ParamPos1}{"Type"};
    my $Parameter_Name = $MethodInfo{1}{$Method}{"Param"}{$ParamPos1}{"Name"};
    my $ParamType2_Id = $MethodInfo{2}{$Method}{"Param"}{$ParamPos2}{"Type"};
    return if(not $ParamType1_Id or not $ParamType2_Id);
    my $Parameter_Location = ($Parameter_Name)?$Parameter_Name:showPos($ParamPos1)." Parameter";
    
    # checking type declaration changes
    my %SubProblems = mergeTypes($ParamType1_Id, $ParamType2_Id);
    foreach my $SubProblemType (keys(%SubProblems))
    {
        foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
        {
            my $NewLocation = ($SubLocation)?$Parameter_Location.".".$SubLocation:$Parameter_Location;
            %{$CompatProblems{$Method}{$SubProblemType}{$NewLocation}}=(
                "Parameter_Type_Name"=>get_TypeName($ParamType1_Id, 1),
                "Parameter_Position"=>$ParamPos1,
                "Parameter_Name"=>$Parameter_Name);
            @{$CompatProblems{$Method}{$SubProblemType}{$NewLocation}}{keys(%{$SubProblems{$SubProblemType}{$SubLocation}})} = values %{$SubProblems{$SubProblemType}{$SubLocation}};
            if($SubLocation!~/\./) {
                $CompatProblems{$Method}{$SubProblemType}{$NewLocation}{"Start_Type_Name"} = get_TypeName($ParamType1_Id, 1);
            }
        }
    }
}

sub detectTypeChange($$$)
{
    my ($Type1_Id, $Type2_Id, $Prefix) = @_;
    my %LocalProblems = ();
    my %Type1 = get_Type($Type1_Id, 1);
    my %Type2 = get_Type($Type2_Id, 2);
    my %Type1_Base = ($Type1{"Type"} eq "array")?get_OneStep_BaseType($Type1_Id, 1):get_BaseType($Type1_Id, 1);
    my %Type2_Base = ($Type2{"Type"} eq "array")?get_OneStep_BaseType($Type2_Id, 2):get_BaseType($Type2_Id, 2);
    return () if(not $Type1{"Name"} or not $Type2{"Name"});
    return () if(not $Type1_Base{"Name"} or not $Type2_Base{"Name"});
    if($Type1_Base{"Name"} ne $Type2_Base{"Name"} and $Type1{"Name"} eq $Type2{"Name"})
    {# base type change
        %{$LocalProblems{"Changed_".$Prefix."_BaseType"}}=(
            "Old_Value"=>$Type1_Base{"Name"},
            "New_Value"=>$Type2_Base{"Name"} );
    }
    elsif($Type1{"Name"} ne $Type2{"Name"})
    {# type change
        %{$LocalProblems{"Changed_".$Prefix."_Type"}}=(
            "Old_Value"=>$Type1{"Name"},
            "New_Value"=>$Type2{"Name"} );
    }
    return %LocalProblems;
}

sub htmlSpecChars($)
{
    my $Str = $_[0];
    if(not defined $Str
    or $Str eq "") {
        return "";
    }
    $Str=~s/\&([^#]|\Z)/&amp;$1/g;
    $Str=~s/</&lt;/g;
    $Str=~s/\-\>/&#45;&gt;/g; # &minus;
    $Str=~s/>/&gt;/g;
    $Str=~s/([^ ])( )([^ ])/$1\@ALONE_SP\@$3/g;
    $Str=~s/ /&#160;/g; # &nbsp;
    $Str=~s/\@ALONE_SP\@/ /g;
    $Str=~s/\n/<br\/>/g;
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
    return $Str;
}

sub highLight_Signature($)
{
    return highLight_Signature_PPos_Italic($_[0], "", 1, 0);
}

sub highLight_Signature_Italic($)
{
    return highLight_Signature_PPos_Italic($_[0], "", 1, 0);
}

sub highLight_Signature_Italic_Color($)
{
    return highLight_Signature_PPos_Italic($_[0], "", 1, 1);
}

sub highLight_Signature_PPos_Italic($$$$)
{
    my ($Signature, $Param_Pos, $ItalicParams, $ColorParams) = @_;
    $Param_Pos = "" if(not defined $Param_Pos);
    if($Signature!~/\)/)
    { # global data
        $Signature = htmlSpecChars($Signature);
        $Signature =~ s!(\[data\])!<span style='color:Black;font-weight:normal;'>$1</span>!g;
        return $Signature;
    }
    my ($Begin, $End, $Return) = ("", "", "");
    if($Signature=~s/\s+:(.+)//g)
    {
        $Return = $1;
    }
    if($Signature=~/(.+)\(.*\)(| \[static\]| \[abstract\])\Z/)
    {
        ($Begin, $End) = ($1, $2);
    }
    $Begin.=" " if($Begin!~/ \Z/);
    my @Parts = ();
    my @SParts = get_s_params($Signature, 1);
    foreach my $Pos (0 .. $#SParts)
    {
        my $Part = $SParts[$Pos];
        $Part=~s/\A\s+|\s+\Z//g;
        my ($Part_Styled, $ParamName) = (htmlSpecChars($Part), "");
        if($Part=~/(\w+)[\,\)]*\Z/i) {
            $ParamName = $1;
        }
        if(not $ParamName) {
            push(@Parts, $Part_Styled);
            next;
        }
        if($ItalicParams and not $TName_Tid{1}{$Part}
        and not $TName_Tid{2}{$Part})
        {
            my $Style = "param";
            if($Param_Pos ne ""
            and $Pos==$Param_Pos) {
                $Style = "focus_p";
            }
            elsif($ColorParams) {
                $Style = "color_p";
            }
            $Part_Styled =~ s!(\W)$ParamName([\,\)]|\Z)!$1<span class=\'$Style\'>$ParamName</span>$2!ig;
        }
        push(@Parts, $Part_Styled);
    }
    if(@Parts)
    {
        foreach my $Num (0 .. $#Parts)
        {
            if($Num==$#Parts)
            { # add ")" to the last parameter
                $Parts[$Num] = "<span class='nowrap'>".$Parts[$Num]." )</span>";
            }
            elsif(length($Parts[$Num])<=45) {
                $Parts[$Num] = "<span class='nowrap'>".$Parts[$Num]."</span>";
            }
        }
        $Signature = htmlSpecChars($Begin)."<span class='sym_p'>(&#160;".join(" ", @Parts)."</span>";
    }
    else {
        $Signature = htmlSpecChars($Begin)."<span class='sym_p'>(&#160;)</span>";
    }
    if($End and $ColorParams) {
        $Signature .= $End;
    }
    if($Return and $ColorParams) {
        $Signature .= "<span class='sym_p nowrap'> &#160;<b>:</b>&#160;&#160;".htmlSpecChars($Return)."</span>";
    }
    $Signature=~s!\[\]![&#160;]!g;
    $Signature=~s!operator=!operator&#160;=!g;
    $Signature=~s!(\[static\]|\[abstract\])!<span class='sym_kind'>$1</span>!g;
    return $Signature;
}

sub get_s_params($$)
{
    my ($Signature, $Comma) = @_;
    if($Signature=~/\((.+)\)/)
    {
        my @Params = split(/,\s*/, $1);
        if($Comma)
        {
            foreach (0 .. $#Params)
            {
                if($_!=$#Params)
                {
                    $Params[$_].=",";
                }
            }
        }
        return @Params;
    }
    return ();
}

sub checkJavaCompiler($)
{# check javac: compile simple program
    my $Cmd = $_[0];
    return if(not $Cmd);
    writeFile($TMP_DIR."/test_javac/Simple.java",
    "public class Simple {
        public Integer f;
        public void method(Integer p) { };
    }");
    chdir($TMP_DIR."/test_javac");
    system("$Cmd Simple.java 2>$TMP_DIR/javac_errors");
    chdir($ORIG_DIR);
    if($?)
    {
        my $Msg = "something is going wrong with the Java compiler (javac):\n";
        my $Err = readFile($TMP_DIR."/javac_errors");
        $Msg .= $Err;
        if($Err=~/elf\/start\.S/ and $Err=~/undefined\s+reference\s+to/)
        { # /usr/lib/gcc/i586-suse-linux/4.5/../../../crt1.o: In function _start:
          # /usr/src/packages/BUILD/glibc-2.11.3/csu/../sysdeps/i386/elf/start.S:115: undefined reference to main
            $Msg .= "\nDid you install a JDK-devel package?";
        }
        exitStatus("Error", $Msg);
    }
}

sub runTests($$$$)
{
    my ($TestsPath, $PackageName, $Path_v1, $Path_v2) = @_;
    # compile with old version of package
    my $JavacCmd = get_CmdPath("javac");
    if(not $JavacCmd) {
        exitStatus("Not_Found", "can't find \"javac\" compiler");
    }
    my $JavaCmd = get_CmdPath("java");
    if(not $JavaCmd) {
        exitStatus("Not_Found", "can't find \"java\" command");
    }
    mkpath($TestsPath."/$PackageName/");
    foreach my $ClassPath (cmd_find($Path_v1,"","*\.class",""))
    {# create a compile-time package copy
        copy($ClassPath, $TestsPath."/$PackageName/");
    }
    system("cd $TestsPath && $JavacCmd -g *.java");
    foreach my $TestSrc (cmd_find($TestsPath,"","*\.java",""))
    {# remove test source
        unlink($TestSrc);
    }
    rmtree($TestsPath."/$PackageName");
    mkpath($TestsPath."/$PackageName/");
    foreach my $ClassPath (cmd_find($Path_v2,"","*\.class",""))
    {# create a run-time package copy
        copy($ClassPath, $TestsPath."/$PackageName/");
    }
    my $TEST_REPORT = "";
    foreach my $TestPath (cmd_find($TestsPath,"","*\.class",1))
    {# run tests
        my $Name = get_filename($TestPath);
        $Name=~s/\.class\Z//g;
        system("cd $TestsPath && $JavaCmd $Name >result.txt 2>&1");
        my $Result = readFile($TestsPath."/result.txt");
        unlink($TestsPath."/result.txt");
        $TEST_REPORT .= "TEST CASE: $Name\n";
        if($Result) {
            $TEST_REPORT .= "RESULT: FAILED\n";
            $TEST_REPORT .= "OUTPUT:\n$Result\n";
        }
        else {
            $TEST_REPORT .= "RESULT: SUCCESS\n";
        }
        $TEST_REPORT .= "\n";
    }
    writeFile("$TestsPath/Journal.txt", $TEST_REPORT);
    rmtree($TestsPath."/$PackageName");
}

sub compileJavaLib($$$)
{
    my ($LibName, $BuildRoot1, $BuildRoot2) = @_;
    my $JavacCmd = get_CmdPath("javac");
    if(not $JavacCmd) {
        exitStatus("Not_Found", "can't find \"javac\" compiler");
    }
    checkJavaCompiler($JavacCmd);
    my $JarCmd = get_CmdPath("jar");
    if(not $JarCmd) {
        exitStatus("Not_Found", "can't find \"jar\" command");
    }
    writeFile("$BuildRoot1/MANIFEST.MF", "Implementation-Version: 1.0\n");
    # space before value, new line
    writeFile("$BuildRoot2/MANIFEST.MF", "Implementation-Version: 2.0\n");
    my (%SrcDir1, %SrcDir2) = ();
    foreach my $Path (cmd_find($BuildRoot1,"f","*.java","")) {
        $SrcDir1{get_dirname($Path)} = 1;
    }
    foreach my $Path (cmd_find($BuildRoot2,"f","*.java","")) {
        $SrcDir2{get_dirname($Path)} = 1;
    }
    my $Src1 = join($SLASH."*.java ", keys(%SrcDir1)).$SLASH."*.java ";
    my $Src2 = join($SLASH."*.java ", keys(%SrcDir2)).$SLASH."*.java ";
    my $BuildCmd1 = "cd $BuildRoot1 && $JavacCmd -g $Src1 && $JarCmd -cmf MANIFEST.MF $LibName.jar TestPackage";
    my $BuildCmd2 = "cd $BuildRoot2 && $JavacCmd -g $Src2 && $JarCmd -cmf MANIFEST.MF $LibName.jar TestPackage";
    system($BuildCmd1);
    if($?) {
        exitStatus("Error", "can't compile classes v.1");
    }
    system($BuildCmd2);
    if($?) {
        exitStatus("Error", "can't compile classes v.2");
    }
    foreach my $SrcPath (cmd_find($BuildRoot1,"","*\.java","")) {
        unlink($SrcPath);
    }
    foreach my $SrcPath (cmd_find($BuildRoot2,"","*\.java","")) {
        unlink($SrcPath);
    }
    return 1;
}

sub readLineNum($$)
{
    my ($Path, $Num) = @_;
    return "" if(not $Path or not -f $Path);
    open (FILE, $Path);
    foreach (1 ... $Num) {
        <FILE>;
    }
    my $Line = <FILE>;
    close(FILE);
    return $Line;
}

sub readAttributes($$)
{
    my ($Path, $Num) = @_;
    return () if(not $Path or not -f $Path);
    my %Attributes = ();
    if(readLineNum($Path, $Num)=~/<!--\s+(.+)\s+-->/)
    {
        foreach my $AttrVal (split(/;/, $1))
        {
            if($AttrVal=~/(.+):(.+)/)
            {
                my ($Name, $Value) = ($1, $2);
                $Attributes{$Name} = $Value;
            }
        }
    }
    return \%Attributes;
}

sub runChecker($$$)
{
    my ($LibName, $Path1, $Path2) = @_;
    writeFile("$LibName/v1.xml", "
        <version>
            1.0
        </version>
        <archives>
            ".get_abs_path($Path1)."
        </archives>");
    writeFile("$LibName/v2.xml", "
        <version>
            2.0
        </version>
        <archives>
            ".get_abs_path($Path2)."
        </archives>");
    my $Cmd = "perl $0 -l $LibName -old $LibName/v1.xml -new $LibName/v2.xml";
    if($OSgroup ne "windows") {
        $Cmd .= " -check-implementation";
    }
    if($Browse) {
        $Cmd .= " -b $Browse";
    }
    if($Quick) {
        $Cmd .= " -quick";
    }
    if($Debug)
    {
        $Cmd .= " -debug";
        print "running $Cmd\n";
    }
    system($Cmd);
    my $Report = "compat_reports/$LibName/1.0_to_2.0/compat_report.html";
    # Binary
    my $BReport = readAttributes($Report, 0);
    my $NProblems = $BReport->{"type_problems_high"}+$BReport->{"type_problems_medium"};
    $NProblems += $BReport->{"method_problems_high"}+$BReport->{"method_problems_medium"};
    $NProblems += $BReport->{"removed"};
    # Source
    my $SReport = readAttributes($Report, 1);
    $NProblems += $SReport->{"type_problems_high"}+$SReport->{"type_problems_medium"};
    $NProblems += $SReport->{"method_problems_high"}+$SReport->{"method_problems_medium"};
    $NProblems += $SReport->{"removed"};
    if($NProblems>=100) {
        print "test result: SUCCESS ($NProblems breaks found)\n\n";
    }
    else {
        print STDERR "test result: FAILED ($NProblems breaks found)\n\n";
    }
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open (FILE, ">".$Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open (FILE, $Path);
    my $Content = join("", <FILE>);
    close(FILE);
    $Content=~s/\r//g;
    return $Content;
}

sub appendFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">>".$Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub get_Report_Header($)
{
    my $Level = $_[0];
    my $Report_Header = "<h1><span class='nowrap'>";
    if($Level eq "Source") {
        $Report_Header .= "Source compatibility";
    }
    elsif($Level eq "Binary") {
        $Report_Header .= "Binary compatibility";
    }
    else {
        $Report_Header .= "API compatibility";
    }
    $Report_Header .= " report for the <span style='color:Blue;'>$TargetLibraryFullName</span> library </span><span class='nowrap'>&#160;between <span style='color:Red;'>".$Descriptor{1}{"Version"}."</span> and <span style='color:Red;'>".$Descriptor{2}{"Version"}."</span> versions</span>";
    if($ClientPath) {
        $Report_Header .= " <span class='nowrap'>&#160;&#160;(relating to the portability of client application <span style='color:Blue;'>".get_filename($ClientPath)."</span>)</span>";
    }
    $Report_Header .= "</h1>\n";
    return $Report_Header;
}

sub get_SourceInfo()
{
    my $CheckedClasses = "<a name='Checked_Classes'></a><h2>Classes (".keys(%{$LibClasses{1}}).")</h2>";
    $CheckedClasses .= "<hr/><div class='class_list'>\n";
    foreach my $Class_Path (keys(%{$LibClasses{1}})) {
        $CheckedClasses .= $LibClasses{1}{$Class_Path}.".".get_filename($Class_Path)."<br/>\n";
    }
    $CheckedClasses .= "</div><br/>$TOP_REF<br/>\n";
    my $CheckedArchives = "<a name='Checked_Archives'></a><h2>Java ARchives (".keys(%{$LibArchives{1}}).")</h2>\n";
    $CheckedArchives .= "<hr/><div class='jar_list'>\n";
    foreach my $ArchivePath (sort {lc($a) cmp lc($b)}  keys(%{$LibArchives{1}})) {
        $CheckedArchives .= get_filename($ArchivePath)."<br/>\n";
    }
    $CheckedArchives .= "</div><br/>$TOP_REF<br/>\n";
    return $CheckedArchives.$CheckedClasses;
}

sub get_TypeProblems_Count($$$)
{
    my ($TypeChanges, $TargetSeverity, $Level) = @_;
    my $Type_Problems_Count = 0;
    foreach my $Type_Name (sort keys(%{$TypeChanges}))
    {
        my %Kinds_Target = ();
        foreach my $Kind (sort keys(%{$TypeChanges->{$Type_Name}}))
        {
            foreach my $Location (sort keys(%{$TypeChanges->{$Type_Name}{$Kind}}))
            {
                my $Target = $TypeChanges->{$Type_Name}{$Kind}{$Location}{"Target"};
                my $Priority = getProblemSeverity($Level, $Kind, $Type_Name, $Target);
                next if($Priority ne $TargetSeverity);
                if($Kinds_Target{$Kind}{$Target}) {
                    next;
                }
                if(cmpSeverities($Type_MaxPriority{$Level}{$Type_Name}{$Kind}{$Target}, $Priority))
                { # select a problem with the highest priority
                    next;
                }
                $Kinds_Target{$Kind}{$Target} = 1;
                $Type_Problems_Count += 1;
            }
        }
    }
    return $Type_Problems_Count;
}

sub show_number($)
{
    if($_[0])
    {
        my $Num = cut_off_number($_[0], 2, 0);
        if($Num eq "0")
        {
            foreach my $P (3 .. 7)
            {
                $Num = cut_off_number($_[0], $P, 1);
                if($Num ne "0") {
                    last;
                }
            }
        }
        if($Num eq "0") {
            $Num = $_[0];
        }
        return $Num;
    }
    return $_[0];
}

sub cut_off_number($$$)
{
    my ($num, $digs_to_cut, $z) = @_;
    if($num!~/\./)
    {
        $num .= ".";
        foreach (1 .. $digs_to_cut-1) {
            $num .= "0";
        }
    }
    elsif($num=~/\.(.+)\Z/ and length($1)<$digs_to_cut-1)
    {
        foreach (1 .. $digs_to_cut - 1 - length($1)) {
            $num .= "0";
        }
    }
    elsif($num=~/\d+\.(\d){$digs_to_cut,}/) {
      $num=sprintf("%.".($digs_to_cut-1)."f", $num);
    }
    $num=~s/\.[0]+\Z//g;
    if($z) {
        $num=~s/(\.[1-9]+)[0]+\Z/$1/g;
    }
    return $num;
}

sub get_Summary($)
{
    my $Level = $_[0];
    my ($Added, $Removed, $M_Problems_High, $M_Problems_Medium, $M_Problems_Low,
    $T_Problems_High, $T_Problems_Medium, $T_Problems_Low, $M_Other, $T_Other) = (0,0,0,0,0,0,0,0,0,0);
    %{$RESULT{$Level}} = (
        "Problems"=>0,
        "Warnings"=>0,
        "Affected"=>0 );
    foreach my $Method (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Method}}))
        {
            if($MethodProblems_Kind{$Level}{$Kind})
            {
                foreach my $Location (sort keys(%{$CompatProblems{$Method}{$Kind}}))
                {
                    my $Type_Name = $CompatProblems{$Method}{$Kind}{$Location}{"Type_Name"};
                    my $Target = $CompatProblems{$Method}{$Kind}{$Location}{"Target"};
                    my $Priority = getProblemSeverity($Level, $Kind, $Type_Name, $Target);
                    if($Kind eq "Added_Method")
                    {
                        if($Level eq "Source")
                        {
                            if($ChangedReturnFromVoid{$Method}) {
                                next;
                            }
                        }
                        $Added+=1;
                    }
                    elsif($Kind eq "Removed_Method")
                    {
                        if($Level eq "Source")
                        {
                            if($ChangedReturnFromVoid{$Method}) {
                                next;
                            }
                        }
                        $Removed+=1;
                        $TotalAffected{$Level}{$Method} = $Priority;
                    }
                    else
                    {
                        if($Priority eq "Safe") {
                            $M_Other += 1;
                        }
                        elsif($Priority eq "High") {
                            $M_Problems_High+=1;
                        }
                        elsif($Priority eq "Medium") {
                            $M_Problems_Medium+=1;
                        }
                        elsif($Priority eq "Low") {
                            $M_Problems_Low+=1;
                        }
                        if(($Priority ne "Low" or $StrictCompat)
                        and $Priority ne "Safe") {
                            $TotalAffected{$Level}{$Method} = $Priority;
                        }
                    }
                }
            }
        }
    }
    my %TypeChanges = ();
    foreach my $Method (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Method}}))
        {
            if($TypeProblems_Kind{$Level}{$Kind})
            {
                foreach my $Location (sort keys(%{$CompatProblems{$Method}{$Kind}}))
                {
                    my $Type_Name = $CompatProblems{$Method}{$Kind}{$Location}{"Type_Name"};
                    my $Target = $CompatProblems{$Method}{$Kind}{$Location}{"Target"};
                    my $Priority = getProblemSeverity($Level, $Kind, $Type_Name, $Target);
                    if(cmpSeverities($Type_MaxPriority{$Level}{$Type_Name}{$Kind}{$Target}, $Priority))
                    { # select a problem with the highest priority
                        next;
                    }
                    if(($Priority ne "Low" or $StrictCompat)
                    and $Priority ne "Safe") {
                        $TotalAffected{$Level}{$Method} = maxSeverity($TotalAffected{$Level}{$Method}, $Priority);
                    }
                    %{$TypeChanges{$Type_Name}{$Kind}{$Location}} = %{$CompatProblems{$Method}{$Kind}{$Location}};
                    $Type_MaxPriority{$Level}{$Type_Name}{$Kind}{$Target} = maxSeverity($Type_MaxPriority{$Level}{$Type_Name}{$Kind}{$Target}, $Priority);
                }
            }
        }
    }
    $T_Problems_High = get_TypeProblems_Count(\%TypeChanges, "High", $Level);
    $T_Problems_Medium = get_TypeProblems_Count(\%TypeChanges, "Medium", $Level);
    $T_Problems_Low = get_TypeProblems_Count(\%TypeChanges, "Low", $Level);
    $T_Other = get_TypeProblems_Count(\%TypeChanges, "Safe", $Level);

    # changed and removed public symbols
    my $SCount = keys(%CheckedMethods);
    if($SCount)
    {
        my %Weight = (
            "High" => 100,
            "Medium" => 50,
            "Low" => 25
        );
        foreach (keys(%{$TotalAffected{$Level}})) {
            $RESULT{$Level}{"Affected"}+=$Weight{$TotalAffected{$Level}{$_}};
        }
        $RESULT{$Level}{"Affected"} = $RESULT{$Level}{"Affected"}/$SCount;
    }
    else {
        $RESULT{$Level}{"Affected"} = 0;
    }
    $RESULT{$Level}{"Affected"} = show_number($RESULT{$Level}{"Affected"});
    if($RESULT{$Level}{"Affected"}>=100) {
        $RESULT{$Level}{"Affected"} = 100;
    }
    
    my ($TestInfo, $TestResults, $Problem_Summary) = ();
    
    # test info
    $TestInfo .= "<h2>Test Info</h2><hr/>\n";
    $TestInfo .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
    $TestInfo .= "<tr><th>Library Name</th><td>$TargetLibraryFullName</td></tr>\n";
    $TestInfo .= "<tr><th>Version #1</th><td>".$Descriptor{1}{"Version"}."</td></tr>\n";
    $TestInfo .= "<tr><th>Version #2</th><td>".$Descriptor{2}{"Version"}."</td></tr>\n";
    if($JoinReport)
    {
        if($Level eq "Binary") {
            $TestInfo .= "<tr><th>Subject</th><td width='150px'>Binary Compatibility</td></tr>\n"; # Run-time
        }
        if($Level eq "Source") {
            $TestInfo .= "<tr><th>Subject</th><td width='150px'>Source Compatibility</td></tr>\n"; # Build-time
        }
    }
    $TestInfo .= "</table>\n";
    
    # test results
    $TestResults .= "<h2>Test Results</h2><hr/>";
    $TestResults .= "<table cellpadding='3' cellspacing='0' class='summary'>";
    
    my $Checked_Archives_Link = "0";
    $Checked_Archives_Link = "<a href='#Checked_Archives' style='color:Blue;'>".keys(%{$LibArchives{1}})."</a>" if(keys(%{$LibArchives{1}})>0);
    $TestResults .= "<tr><th>Total Java ARchives</th><td>$Checked_Archives_Link</td></tr>";
    
    my $Checked_Classes_Link = "0";
    $Checked_Classes_Link = "<a href='#Checked_Classes' style='color:Blue;'>".keys(%{$LibClasses{1}})."</a>" if(keys(%{$LibClasses{1}})>0);
    $TestResults .= "<tr><th>Total Classes</th><td>$Checked_Classes_Link</td></tr>";
    
    $TestResults .= "<tr><th>Total Methods / Types</th><td>".keys(%CheckedMethods)." / ".keys(%CheckedTypes)."</td></tr>";
    
    my $Verdict = "";
    $RESULT{$Level}{"Problems"} += $Removed+$M_Problems_High+$T_Problems_High+$T_Problems_Medium+$M_Problems_Medium;
    if($StrictCompat) {
        $RESULT{$Level}{"Problems"}+=$T_Problems_Low+$M_Problems_Low;
    }
    else {
        $RESULT{$Level}{"Warnings"}+=$T_Problems_Low+$M_Problems_Low;
    }
    if($RESULT{$Level}{"Problems"}) {
        $Verdict = "<span style='color:Red;'><b>Incompatible</b></span>";
    }
    else {
        $Verdict = "<span style='color:Green;'><b>Compatible</b></span>";
    }
    my $META_DATA = "kind:".lc($Level).";";
    $META_DATA .= $RESULT{$Level}{"Problems"}?"verdict:incompatible;":"verdict:compatible;";
    $TestResults .= "<tr><th>Verdict</th>";
    if($RESULT{$Level}{"Problems"}) {
        $TestResults .= "<td><span style='color:Red;'><b>Incompatible<br/>(".$RESULT{$Level}{"Affected"}."%)</b></span></td>";
    }
    else {
        $TestResults .= "<td><span style='color:Green;'><b>Compatible</b></span></td>";
    }
    $TestResults .= "</tr>\n";
    $TestResults .= "</table>\n";
    
    $META_DATA .= "affected:".$RESULT{$Level}{"Affected"}.";";# in percents
    
    # Problem Summary
    $Problem_Summary .= "<h2>Problem Summary</h2><hr/>";
    $Problem_Summary .= "<table cellpadding='3' cellspacing='0' class='summary'>";
    $Problem_Summary .= "<tr><th></th><th style='text-align:center;'>Severity</th><th style='text-align:center;'>Count</th></tr>";
    
    if(not $ShortMode)
    {
        my $Added_Link = "0";
        if($Added>0)
        {
            if($JoinReport) {
                $Added_Link = "<a href='#".$Level."_Added' style='color:Blue;'>$Added</a>";
            }
            else {
                $Added_Link = "<a href='#Added' style='color:Blue;'>$Added</a>";
            }
        }
        $META_DATA .= "added:$Added;";
        $Problem_Summary .= "<tr><th>Added Methods</th><td>-</td><td".getStyle("I", "A", $Added).">$Added_Link</td></tr>";
    }
    
    my $Removed_Link = "0";
    if($Removed>0)
    {
        if($JoinReport) {
            $Removed_Link = "<a href='#".$Level."_Removed' style='color:Blue;'>$Removed</a>"
        }
        else {
            $Removed_Link = "<a href='#Removed' style='color:Blue;'>$Removed</a>"
        }
    }
    $META_DATA .= "removed:$Removed;";
    $Problem_Summary .= "<tr><th>Removed Methods</th>";
    $Problem_Summary .= "<td>High</td><td".getStyle("I", "R", $Removed).">$Removed_Link</td></tr>";
    
    my $TH_Link = "0";
    $TH_Link = "<a href='#".get_Anchor("Type", $Level, "High")."' style='color:Blue;'>$T_Problems_High</a>" if($T_Problems_High>0);
    $META_DATA .= "type_problems_high:$T_Problems_High;";
    $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Data Types</th>";
    $Problem_Summary .= "<td>High</td><td".getStyle("T", "H", $T_Problems_High).">$TH_Link</td></tr>";
    
    my $TM_Link = "0";
    $TM_Link = "<a href='#".get_Anchor("Type", $Level, "Medium")."' style='color:Blue;'>$T_Problems_Medium</a>" if($T_Problems_Medium>0);
    $META_DATA .= "type_problems_medium:$T_Problems_Medium;";
    $Problem_Summary .= "<tr><td>Medium</td><td".getStyle("T", "M", $T_Problems_Medium).">$TM_Link</td></tr>";
    
    my $TL_Link = "0";
    $TL_Link = "<a href='#".get_Anchor("Type", $Level, "Low")."' style='color:Blue;'>$T_Problems_Low</a>" if($T_Problems_Low>0);
    $META_DATA .= "type_problems_low:$T_Problems_Low;";
    $Problem_Summary .= "<tr><td>Low</td><td".getStyle("T", "L", $T_Problems_Low).">$TL_Link</td></tr>";
    
    my $MH_Link = "0";
    $MH_Link = "<a href='#".get_Anchor("Method", $Level, "High")."' style='color:Blue;'>$M_Problems_High</a>" if($M_Problems_High>0);
    $META_DATA .= "method_problems_high:$M_Problems_High;";
    $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Methods</th>";
    $Problem_Summary .= "<td>High</td><td".getStyle("M", "H", $M_Problems_High).">$MH_Link</td></tr>";
    
    my $MM_Link = "0";
    $MM_Link = "<a href='#".get_Anchor("Method", $Level, "Medium")."' style='color:Blue;'>$M_Problems_Medium</a>" if($M_Problems_Medium>0);
    $META_DATA .= "method_problems_medium:$M_Problems_Medium;";
    $Problem_Summary .= "<tr><td>Medium</td><td".getStyle("M", "M", $M_Problems_Medium).">$MM_Link</td></tr>";
    
    my $ML_Link = "0";
    $ML_Link = "<a href='#".get_Anchor("Method", $Level, "Low")."' style='color:Blue;'>$M_Problems_Low</a>" if($M_Problems_Low>0);
    $META_DATA .= "method_problems_low:$M_Problems_Low;";
    $Problem_Summary .= "<tr><td>Low</td><td".getStyle("M", "L", $M_Problems_Low).">$ML_Link</td></tr>";
    
    if($CheckImpl and $Level eq "Binary" and not $Quick)
    {
        my $ChangedImpl_Link = "0";
        $ChangedImpl_Link = "<a href='#Changed_Implementation' style='color:Blue;'>".keys(%ImplProblems)."</a>" if(keys(%ImplProblems)>0);
        $META_DATA .= "changed_implementation:".keys(%ImplProblems).";";
        $Problem_Summary .= "<tr><th>Problems with<br/>Implementation</th><td>Low</td><td".getStyle("Imp", "L", int(keys(%ImplProblems))).">$ChangedImpl_Link</td></tr>";
        $RESULT{$Level}{"Warnings"}+=keys(%ImplProblems);
    }
    # Safe Changes
    if($T_Other)
    {
        my $TS_Link = "<a href='#".get_Anchor("Type", $Level, "Safe")."' style='color:Blue;'>$T_Other</a>";
        $Problem_Summary .= "<tr><th>Other Changes<br/>in Data Types</th><td>-</td><td".getStyle("T", "S", $T_Other).">$TS_Link</td></tr>\n";
    }
    
    if($M_Other)
    {
        my $MS_Link = "<a href='#".get_Anchor("Method", $Level, "Safe")."' style='color:Blue;'>$M_Other</a>";
        $Problem_Summary .= "<tr><th>Other Changes<br/>in Methods</th><td>-</td><td".getStyle("M", "S", $M_Other).">$MS_Link</td></tr>\n";
    }
    $META_DATA .= "tool_version:$TOOL_VERSION";
    $Problem_Summary .= "</table>\n";
    return ($TestInfo.$TestResults.$Problem_Summary, $META_DATA);
}

sub getStyle($$$)
{
    my ($Subj, $Act, $Num) = @_;
    my %Style = (
        "A"=>"new",
        "R"=>"failed",
        "S"=>"passed",
        "L"=>"warning",
        "M"=>"failed",
        "H"=>"failed"
    );
    if($Num>0) {
        return " class='".$Style{$Act}."'";
    }
    return "";
}

sub get_Anchor($$$)
{
    my ($Kind, $Level, $Severity) = @_;
    if($JoinReport)
    {
        if($Severity eq "Safe") {
            return "Other_".$Level."_Changes_In_".$Kind."s";
        }
        else {
            return $Kind."_".$Level."_Problems_".$Severity;
        }
    }
    else
    {
        if($Severity eq "Safe") {
            return "Other_Changes_In_".$Kind."s";
        }
        else {
            return $Kind."_Problems_".$Severity;
        }
    }
}

sub get_Report_Implementation()
{
    my ($CHANGED_IMPLEMENTATION, %MethodInArchiveClass);
    foreach my $Method (sort keys(%ImplProblems))
    {
        my $ArchiveName = $MethodInfo{1}{$Method}{"Archive"};
        my $ClassName = get_ShortName($MethodInfo{1}{$Method}{"Class"}, 1);
        $MethodInArchiveClass{$ArchiveName}{$ClassName}{$Method} = 1;
    }
    my $Changed_Number = 0;
    foreach my $ArchiveName (sort {lc($a) cmp lc($b)} keys(%MethodInArchiveClass))
    {
        foreach my $ClassName (sort {lc($a) cmp lc($b)} keys(%{$MethodInArchiveClass{$ArchiveName}}))
        {
            $CHANGED_IMPLEMENTATION .= "<span class='jar'>$ArchiveName</span>, <span class='cname'>$ClassName.class</span><br/>\n";
            my %NameSpace_Method = ();
            foreach my $Method (keys(%{$MethodInArchiveClass{$ArchiveName}{$ClassName}})) {
                $NameSpace_Method{$MethodInfo{1}{$Method}{"Package"}}{$Method} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Method))
            {
                $CHANGED_IMPLEMENTATION .= ($NameSpace)?"<span class='package_title'>package</span> <span class='package'>$NameSpace</span>"."<br/>\n":"";
                my @SortedMethods = sort {lc($MethodInfo{1}{$a}{"Signature"}) cmp lc($MethodInfo{1}{$b}{"Signature"})} keys(%{$NameSpace_Method{$NameSpace}});
                foreach my $Method (@SortedMethods)
                {
                    $Changed_Number += 1;
                    my $Signature = $MethodInfo{1}{$Method}{"Signature"};
                    if($NameSpace) {
                        $Signature=~s/(\W|\A)\Q$NameSpace\E\.(\w)/$1$2/g;
                    }
                    my $SubReport = insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[run-time name: <b>".htmlSpecChars($Method)."</b>]</span>".$ImplProblems{$Method}{"Diff"}."<br/><br/>".$ContentDivEnd."\n");
                    $CHANGED_IMPLEMENTATION .= $SubReport;
                }
            }
            $CHANGED_IMPLEMENTATION .= "<br/>\n";
        }
    }
    if($CHANGED_IMPLEMENTATION) {
        $CHANGED_IMPLEMENTATION = "<a name='Changed_Implementation'></a><h2>Problems with Implementation ($Changed_Number)</h2><hr/>\n".$CHANGED_IMPLEMENTATION.$TOP_REF."<br/>\n";
    }
    return $CHANGED_IMPLEMENTATION;
}

sub get_Report_Added($)
{
    return "" if($ShortMode);
    my $Level = $_[0];
    my ($ADDED_METHODS, %MethodAddedInArchiveClass);
    foreach my $Method (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Method}}))
        {
            if($Kind eq "Added_Method") {
                my $ArchiveName = $MethodInfo{2}{$Method}{"Archive"};
                my $ClassName = get_ShortName($MethodInfo{2}{$Method}{"Class"}, 2);
                if($Level eq "Source")
                {
                    if($ChangedReturnFromVoid{$Method}) {
                        next;
                    }
                }
                $MethodAddedInArchiveClass{$ArchiveName}{$ClassName}{$Method} = 1;
            }
        }
    }
    my $Added_Number = 0;
    foreach my $ArchiveName (sort {lc($a) cmp lc($b)} keys(%MethodAddedInArchiveClass))
    {
        foreach my $ClassName (sort {lc($a) cmp lc($b)} keys(%{$MethodAddedInArchiveClass{$ArchiveName}}))
        {
            $ADDED_METHODS .= "<span class='jar'>$ArchiveName</span>, <span class='cname'>$ClassName.class</span><br/>\n";
            my %NameSpace_Method = ();
            foreach my $Method (keys(%{$MethodAddedInArchiveClass{$ArchiveName}{$ClassName}}))
            {
                $NameSpace_Method{$MethodInfo{2}{$Method}{"Package"}}{$Method} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Method))
            {
                $ADDED_METHODS .= ($NameSpace)?"<span class='package_title'>package</span> <span class='package'>$NameSpace</span><br/>\n":"";
                my @SortedMethods = sort {lc($MethodInfo{2}{$a}{"Signature"}) cmp lc($MethodInfo{2}{$b}{"Signature"})} keys(%{$NameSpace_Method{$NameSpace}});
                foreach my $Method (@SortedMethods)
                {
                    $Added_Number += 1;
                    my $Signature = $MethodInfo{2}{$Method}{"Signature"};
                    if($NameSpace) {
                        $Signature=~s/(\W|\A)\Q$NameSpace\E\.(\w)/$1$2/g;
                    }
                    $ADDED_METHODS .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[run-time name: <b>".htmlSpecChars($Method)."</b>]</span><br/><br/>".$ContentDivEnd."\n");
                }
            }
            $ADDED_METHODS .= "<br/>\n";
        }
    }
    if($ADDED_METHODS)
    {
        my $Anchor = "<a name='Added'></a>";
        if($JoinReport) {
            $Anchor = "<a name='".$Level."_Added'></a>";
        }
        $ADDED_METHODS = $Anchor."<h2>Added Methods ($Added_Number)</h2><hr/>\n".$ADDED_METHODS.$TOP_REF."<br/>\n";
    }
    return $ADDED_METHODS;
}

sub get_Report_Removed($)
{
    my $Level = $_[0];
    my ($REMOVED_METHODS, %MethodRemovedFromArchiveClass);
    foreach my $Method (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Method}}))
        {
            if($Kind eq "Removed_Method")
            {
                if($Level eq "Source")
                {
                    if($ChangedReturnFromVoid{$Method}) {
                        next;
                    }
                }
                my $ArchiveName = $MethodInfo{1}{$Method}{"Archive"};
                my $ClassName = get_ShortName($MethodInfo{1}{$Method}{"Class"}, 1);
                $MethodRemovedFromArchiveClass{$ArchiveName}{$ClassName}{$Method} = 1;
            }
        }
    }
    my $Removed_Number = 0;
    foreach my $ArchiveName (sort {lc($a) cmp lc($b)} keys(%MethodRemovedFromArchiveClass))
    {
        foreach my $ClassName (sort {lc($a) cmp lc($b)} keys(%{$MethodRemovedFromArchiveClass{$ArchiveName}}))
        {
            $REMOVED_METHODS .= "<span class='jar'>$ArchiveName</span>, <span class='cname'>$ClassName.class</span><br/>\n";
            my %NameSpace_Method = ();
            foreach my $Method (keys(%{$MethodRemovedFromArchiveClass{$ArchiveName}{$ClassName}}))
            {
                $NameSpace_Method{$MethodInfo{1}{$Method}{"Package"}}{$Method} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Method))
            {
                $REMOVED_METHODS .= ($NameSpace)?"<span class='package_title'>package</span> <span class='package'>$NameSpace</span><br/>\n":"";
                my @SortedMethods = sort {lc($MethodInfo{1}{$a}{"Signature"}) cmp lc($MethodInfo{1}{$b}{"Signature"})} keys(%{$NameSpace_Method{$NameSpace}});
                foreach my $Method (@SortedMethods)
                {
                    $Removed_Number += 1;
                    my $Signature = $MethodInfo{1}{$Method}{"Signature"};
                    if($NameSpace) {
                        $Signature=~s/(\W|\A)\Q$NameSpace\E\.(\w)/$1$2/g;
                    }
                    $REMOVED_METHODS .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[run-time name: <b>".htmlSpecChars($Method)."</b>]</span><br/><br/>".$ContentDivEnd."\n");
                }
            }
            $REMOVED_METHODS .= "<br/>\n";
        }
    }
    if($REMOVED_METHODS)
    {
        my $Anchor = "<a name='Removed'></a><a name='Withdrawn'></a>";
        if($JoinReport) {
            $Anchor = "<a name='".$Level."_Removed'></a><a name='".$Level."_Withdrawn'></a>";
        }
        $REMOVED_METHODS = $Anchor."<h2>Removed Methods ($Removed_Number)</h2><hr/>\n".$REMOVED_METHODS.$TOP_REF."<br/>\n";
    }
    return $REMOVED_METHODS;
}

sub get_Report_MethodProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my ($METHOD_PROBLEMS, %MethodInArchiveClass);
    foreach my $Method (sort keys(%CompatProblems))
    {
        next if($Method=~/\A([^\@\$\?]+)[\@\$]+/ and defined $CompatProblems{$1});
        foreach my $Kind (sort keys(%{$CompatProblems{$Method}}))
        {
            if($MethodProblems_Kind{$Level}{$Kind}
            and $Kind ne "Added_Method" and $Kind ne "Removed_Method")
            {
                my $ArchiveName = $MethodInfo{1}{$Method}{"Archive"};
                my $ClassName = get_ShortName($MethodInfo{1}{$Method}{"Class"}, 1);
                $MethodInArchiveClass{$ArchiveName}{$ClassName}{$Method} = 1;
            }
        }
    }
    my $Problems_Number = 0;
    foreach my $ArchiveName (sort {lc($a) cmp lc($b)} keys(%MethodInArchiveClass))
    {
        foreach my $ClassName (sort {lc($a) cmp lc($b)} keys(%{$MethodInArchiveClass{$ArchiveName}}))
        {
            my ($ARCHIVE_CLASS_REPORT, %NameSpace_Method) = ();
            foreach my $Method (keys(%{$MethodInArchiveClass{$ArchiveName}{$ClassName}}))
            {
                $NameSpace_Method{$MethodInfo{1}{$Method}{"Package"}}{$Method} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Method))
            {
                my $NAMESPACE_REPORT = "";
                my @SortedMethods = sort {lc($MethodInfo{1}{$a}{"Signature"}) cmp lc($MethodInfo{1}{$b}{"Signature"})} keys(%{$NameSpace_Method{$NameSpace}});
                foreach my $Method (@SortedMethods)
                {
                    my $Signature = $MethodInfo{1}{$Method}{"Signature"};
                    my $ShortSignature = get_Signature($Method, 1, "Short");
                    my $ClassName_Full = get_TypeName($MethodInfo{1}{$Method}{"Class"}, 1);
                    my $MethodProblemsReport = "";
                    my $ProblemNum = 1;
                    foreach my $Kind (keys(%{$CompatProblems{$Method}}))
                    {
                        foreach my $Location (keys(%{$CompatProblems{$Method}{$Kind}}))
                        {
                            my %Problems = %{$CompatProblems{$Method}{$Kind}{$Location}};
                            my $Type_Name = $Problems{"Type_Name"};
                            my $Target = $Problems{"Target"};
                            my $Priority = getProblemSeverity($Level, $Kind, $Type_Name, $Target);
                            if($Priority ne $TargetSeverity) {
                                next;
                            }
                            my ($Change, $Effect) = ("", "");
                            my $Old_Value = htmlSpecChars($Problems{"Old_Value"});
                            my $New_Value = htmlSpecChars($Problems{"New_Value"});
                            my $Parameter_Position = $Problems{"Parameter_Position"};
                            my $Parameter_Position_Str = showPos($Parameter_Position);
                            if($Kind eq "Method_Became_Static")
                            {
                                $Change = "Method became <b>static</b>.\n";
                                $Effect = "A client program may be interrupted by <b>NoSuchMethodError</b> exception.";
                            }
                            elsif($Kind eq "Method_Became_NonStatic")
                            {
                                $Change = "Method became <b>non-static</b>.\n";
                                if($Level eq "Binary") {
                                    $Effect = "A client program may be interrupted by <b>NoSuchMethodError</b> exception.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: non-static method $ShortSignature cannot be referenced from a static context.";
                                }
                            }
                            elsif($Kind eq "Changed_Method_Return_From_Void")
                            {
                                $Change = "Return value type has been changed from <b>void</b> to <b>".htmlSpecChars($New_Value)."</b>.\n";
                                $Effect = "This method has been removed because the return type is part of the method signature.";
                            }
                            elsif($Kind eq "Static_Method_Became_Final")
                            {# Source Only
                                $Change = "Method became <b>final</b>.\n";
                                $Effect = "Recompilation of a client program may be terminated with the message: $ShortSignature in client class C cannot override $ShortSignature in $ClassName_Full; overridden method is final.";
                            }
                            elsif($Kind eq "NonStatic_Method_Became_Final")
                            {
                                $Change = "Method became <b>final</b>.\n";
                                if($Level eq "Binary") {
                                    $Effect = "A client program trying to reimplement this method may be interrupted by <b>VerifyError</b> exception.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: $ShortSignature in client class C cannot override $ShortSignature in $ClassName_Full; overridden method is final.";
                                }
                            }
                            elsif($Kind eq "Method_Became_Abstract")
                            {
                                $Change = "Method became <b>abstract</b>.\n";
                                if($Level eq "Binary") {
                                    $Effect = "A client program trying to create an instance of the method's class may be interrupted by <b>InstantiationError</b> exception.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: A client class C is not abstract and does not override abstract method $ShortSignature in $ClassName_Full.";
                                }
                            }
                            elsif($Kind eq "Method_Became_NonAbstract")
                            {
                                $Change = "Method became <b>non-abstract</b>.\n";
                                $Effect = "A client program may change behavior.";
                            }
                            elsif($Kind eq "Method_Became_Synchronized")
                            {
                                $Change = "Method became <b>synchronized</b>.\n";
                                $Effect = "A multi-threaded client program may change behavior.";
                            }
                            elsif($Kind eq "Method_Became_NonSynchronized")
                            {
                                $Change = "Method became <b>non-synchronized</b>.\n";
                                $Effect = "A multi-threaded client program may change behavior.";
                            }
                            elsif($Kind eq "Changed_Method_Access")
                            {
                                $Change = "Access level has been changed from <span class='nowrap'><b>".htmlSpecChars($Old_Value)."</b></span> to <span class='nowrap'><b>".htmlSpecChars($New_Value)."</b></span>.";
                                if($Level eq "Binary") {
                                    $Effect = "A client program may be interrupted by <b>IllegalAccessError</b> exception.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: $ShortSignature has $New_Value access in $ClassName_Full.";
                                }
                            }
                            elsif($Kind eq "Abstract_Method_Added_Checked_Exception")
                            {# Source Only
                                $Change = "Added <b>$Target</b> exception thrown.\n";
                                $Effect = "Recompilation of a client program may be terminated with the message: unreported exception $Target must be caught or declared to be thrown.";
                            }
                            elsif($Kind eq "NonAbstract_Method_Added_Checked_Exception")
                            {
                                $Change = "Added <b>$Target</b> exception thrown.\n";
                                if($Level eq "Binary") {
                                    $Effect = "A client program may be interrupted by added exception.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: unreported exception $Target must be caught or declared to be thrown.";
                                }
                            }
                            elsif($Kind eq "Abstract_Method_Removed_Checked_Exception")
                            {# Source Only
                                $Change = "Removed <b>$Target</b> exception thrown.\n";
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot override $ShortSignature in $ClassName_Full; overridden method does not throw $Target.";
                            }
                            elsif($Kind eq "NonAbstract_Method_Removed_Checked_Exception")
                            {
                                $Change = "Removed <b>$Target</b> exception thrown.\n";
                                if($Level eq "Binary") {
                                    $Effect = "A client program may change behavior because the removed exception will not be thrown any more and client will not catch and handle it.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: cannot override $ShortSignature in $ClassName_Full; overridden method does not throw $Target.";
                                }
                            }
                            elsif($Kind eq "Added_Unchecked_Exception")
                            {# Binary Only
                                $Change = "Added <b>$Target</b> exception thrown.\n";
                                $Effect = "A client program may be interrupted by added exception.";
                            }
                            elsif($Kind eq "Removed_Unchecked_Exception")
                            {# Binary Only
                                $Change = "Removed <b>$Target</b> exception thrown.\n";
                                $Effect = "A client program may change behavior because the removed exception will not be thrown any more and client will not catch and handle it.";
                            }
                            if($Change)
                            {
                                $MethodProblemsReport .= "<tr><th align='center'>$ProblemNum</th><td align='left' valign='top'>".$Change."</td><td align='left' valign='top'>".$Effect."</td></tr>\n";
                                $ProblemNum += 1;
                                $Problems_Number += 1;
                            }
                        }
                    }
                    $ProblemNum -= 1;
                    if($MethodProblemsReport)
                    {
                        $NAMESPACE_REPORT .= $ContentSpanStart."<span class='extension'>[+]</span> ".highLight_Signature_Italic_Color($Signature)." ($ProblemNum)".$ContentSpanEnd."<br/>\n$ContentDivStart<span class='mangled'>&#160;&#160;[run-time name: <b>".htmlSpecChars($Method)."</b>]</span><br/>\n";
                        if($NameSpace) {
                            $NAMESPACE_REPORT=~s/(\W|\A)\Q$NameSpace\E\.(\w)/$1$2/g;
                        }
                        $NAMESPACE_REPORT .= "<table class='ptable'><tr><th width='2%'></th><th width='47%'>Change</th><th>Effect</th></tr>$MethodProblemsReport</table><br/>$ContentDivEnd\n";
                        $NAMESPACE_REPORT = insertIDs($NAMESPACE_REPORT);
                    }
                }
                if($NAMESPACE_REPORT) {
                    $ARCHIVE_CLASS_REPORT .= (($NameSpace)?"<span class='package_title'>package</span> <span class='package'>$NameSpace</span>"."<br/>\n":"").$NAMESPACE_REPORT;
                }
            }
            if($ARCHIVE_CLASS_REPORT) {
                $METHOD_PROBLEMS .= "<span class='jar'>$ArchiveName</span>, <span class='cname'>$ClassName</span><br/>\n".$ARCHIVE_CLASS_REPORT."<br/>";
            }
        }
    }
    if($METHOD_PROBLEMS)
    {
        my $Title = "Problems with Methods, $TargetSeverity Severity";
        if($TargetSeverity eq "Safe")
        { # Safe Changes
            $Title = "Other Changes in Methods";
        }
        $METHOD_PROBLEMS = "<a name='".get_Anchor("Method", $Level, $TargetSeverity)."'></a>\n<h2>$Title ($Problems_Number)</h2><hr/>\n".$METHOD_PROBLEMS.$TOP_REF."<br/>\n";
    }
    return $METHOD_PROBLEMS;
}

sub get_Report_TypeProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my ($TYPE_PROBLEMS, %TypeArchive, %TypeChanges) = ();
    foreach my $Method (sort keys(%CompatProblems))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Method}}))
        {
            if($TypeProblems_Kind{$Level}{$Kind})
            {
                foreach my $Location (sort keys(%{$CompatProblems{$Method}{$Kind}}))
                {
                    my $Type_Name = $CompatProblems{$Method}{$Kind}{$Location}{"Type_Name"};
                    my $Target = $CompatProblems{$Method}{$Kind}{$Location}{"Target"};
                    my $Severity = getProblemSeverity($Level, $Kind, $Type_Name, $Target);
                    if($Severity eq "Safe"
                    and $TargetSeverity ne "Safe") {
                        next;
                    }
                    if(cmpSeverities($Type_MaxPriority{$Level}{$Type_Name}{$Kind}{$Target}, $Severity))
                    {# select a problem with the highest priority
                        next;
                    }
                    %{$TypeChanges{$Type_Name}{$Kind}{$Location}} = %{$CompatProblems{$Method}{$Kind}{$Location}};
                    my $ArchiveName = $TypeInfo{1}{$TName_Tid{1}{$Type_Name}}{"Archive"};
                    $TypeArchive{$ArchiveName}{$Type_Name} = 1;
                }
            }
        }
    }
    my $Problems_Number = 0;
    foreach my $ArchiveName (sort {lc($a) cmp lc($b)} keys(%TypeArchive))
    {
        my ($HEADER_REPORT, %NameSpace_Type) = ();
        foreach my $TypeName (keys(%{$TypeArchive{$ArchiveName}}))
        {
            $NameSpace_Type{$TypeInfo{1}{$TName_Tid{1}{$TypeName}}{"Package"}}{$TypeName} = 1;
        }
        foreach my $NameSpace (sort keys(%NameSpace_Type))
        {
            my $NAMESPACE_REPORT = "";
            my @SortedTypes = sort {lc($a) cmp lc($b)} keys(%{$NameSpace_Type{$NameSpace}});
            foreach my $TypeName (@SortedTypes)
            {
                my $ProblemNum = 1;
                my ($TypeProblemsReport, %Kinds_Locations, %Kinds_Target) = ();
                foreach my $Kind (sort keys(%{$TypeChanges{$TypeName}}))
                {
                    foreach my $Location (sort keys(%{$TypeChanges{$TypeName}{$Kind}}))
                    {
                        my $Target = $TypeChanges{$TypeName}{$Kind}{$Location}{"Target"};
                        my $Priority = getProblemSeverity($Level, $Kind, $TypeName, $Target);
                        if($Priority ne $TargetSeverity) {
                            next;
                        }
                        $Kinds_Locations{$Kind}{$Location} = 1;
                        my ($Change, $Effect) = ("", "");
                        my %Problems = %{$TypeChanges{$TypeName}{$Kind}{$Location}};
                        next if($Kinds_Target{$Kind}{$Target});
                        $Kinds_Target{$Kind}{$Target} = 1;
                        my $Old_Value = $Problems{"Old_Value"};
                        my $New_Value = $Problems{"New_Value"};
                        my $Field_Type = $Problems{"Field_Type"};
                        my $Field_Value = $Problems{"Field_Value"};
                        my $Type_Type = $Problems{"Type_Type"};
                        my $Add_Effect = $Problems{"Add_Effect"};
                        if($Kind eq "NonAbstract_Class_Added_Abstract_Method")
                        {
                            my $ShortSignature = get_Signature($Target, 2, "Short");
                            my $ClassName_Full = get_TypeName($MethodInfo{2}{$Target}{"Class"}, 2);
                            $Change = "Abstract method ".black_name($MethodInfo{2}{$Target}{"Signature"})." has been added to this $Type_Type.";
                            if($Level eq "Binary") {
                                $Effect = "This class became <b>abstract</b> and a client program may be interrupted by <b>InstantiationError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method <b>$ShortSignature</b> in <b>$ClassName_Full</b>.";
                            }
                        }
                        elsif($Kind eq "Abstract_Class_Added_Abstract_Method")
                        {
                            my $ShortSignature = get_Signature($Target, 2, "Short");
                            my $ClassName_Full = get_TypeName($MethodInfo{2}{$Target}{"Class"}, 2);
                            $Change = "Abstract method ".black_name($MethodInfo{2}{$Target}{"Signature"})." has been added to this $Type_Type.";
                            if($Level eq "Binary")
                            {
                                if($Add_Effect) {
                                    $Effect = "A client program may be interrupted by <b>AbstractMethodError</b> exception.".$Add_Effect;
                                }
                                else {
                                    $Effect = "No effect.";
                                }
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method <b>$ShortSignature</b> in <b>$ClassName_Full</b>.";
                            }
                        }
                        elsif($Kind eq "Class_Removed_Abstract_Method"
                        or $Kind eq "Interface_Removed_Abstract_Method")
                        {
                            my $ShortSignature = get_Signature($Target, 1, "Short");
                            my $ClassName_Full = get_TypeName($MethodInfo{1}{$Target}{"Class"}, 1);
                            $Change = "Abstract method ".black_name($MethodInfo{1}{$Target}{"Signature"})." has been removed from this $Type_Type.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoSuchMethodError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find method <b>$ShortSignature</b> in $Type_Type <b>$ClassName_Full</b>.";
                            }
                        }
                        elsif($Kind eq "Interface_Added_Abstract_Method")
                        {
                            my $ShortSignature = get_Signature($Target, 2, "Short");
                            my $ClassName_Full = get_TypeName($MethodInfo{2}{$Target}{"Class"}, 2);
                            $Change = "Abstract method ".black_name($MethodInfo{2}{$Target}{"Signature"})." has been added to this $Type_Type.";
                            if($Level eq "Binary")
                            {
                                if($Add_Effect) {
                                    $Effect = "A client program may be interrupted by <b>AbstractMethodError</b> exception.".$Add_Effect;
                                }
                                else {
                                    $Effect = "No effect.";
                                }
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method <b>$ShortSignature</b> in <b>$ClassName_Full</b>.";
                            }
                        }
                        elsif($Kind eq "Class_Method_Became_Abstract")
                        {
                            my $ShortSignature = get_Signature($Target, 1, "Short");
                            my $ClassName_Full = get_TypeName($MethodInfo{1}{$Target}{"Class"}, 1);
                            $Change = "Method ".black_name($MethodInfo{1}{$Target}{"Signature"})." became <b>abstract</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>InstantiationError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method <b>$ShortSignature</b> in <b>$ClassName_Full</b>.";
                            }
                        }
                        elsif($Kind eq "Class_Method_Became_NonAbstract")
                        {
                            $Change = "Abstract method ".black_name($MethodInfo{1}{$Target}{"Signature"})." became <b>non-abstract</b>.";
                            $Effect = "Some methods in this class may change behavior.";
                        }
                        elsif($Kind eq "Class_Overridden_Method")
                        {
                            $Change = "Method ".black_name($Old_Value)." has been overridden by ".black_name($New_Value);
                            $Effect = "Method ".black_name($New_Value)." will be called instead of ".black_name($Old_Value)." in a client program.";
                        }
                        elsif($Kind eq "Class_Method_Moved_Up_Hierarchy")
                        {
                            $Change = "Method ".black_name($Old_Value)." has been moved up type hierarchy to ".black_name($New_Value);
                            $Effect = "Method ".black_name($New_Value)." will be called instead of ".black_name($Old_Value)." in a client program.";
                        }
                        elsif($Kind eq "Abstract_Class_Added_Super_Interface")
                        {
                            $Change = "Added super-interface <b>".htmlSpecChars($Target)."</b>.";
                            if($Level eq "Binary")
                            {
                                if($Add_Effect) {
                                    $Effect = "If abstract methods from an added super-interface must be implemented by client then it may be interrupted by <b>AbstractMethodError</b> exception.".$Add_Effect;
                                }
                                else {
                                    $Effect = "No effect.";
                                }
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method in <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Interface_Added_Super_Interface")
                        {
                            $Change = "Added super-interface <b>".htmlSpecChars($Target)."</b>.";
                            if($Level eq "Binary")
                            {
                                if($Add_Effect) {
                                    $Effect = "If abstract methods from an added super-interface must be implemented by client then it may be interrupted by <b>AbstractMethodError</b> exception.".$Add_Effect;
                                }
                                else {
                                    $Effect = "No effect.";
                                }
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method in <b>$Target</b>.";
                            }
                        }
                        elsif($Kind eq "Interface_Added_Super_Constant_Interface")
                        {
                            $Change = "Added super-interface <b>".htmlSpecChars($Target)."</b> containing constants only.";
                            if($Level eq "Binary") {
                                $Effect = "A static field from a super-interface of a client class may hide a field (with the same name) inherited from a super-class and cause <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Effect = "A static field from a super-interface of a client class may hide a field (with the same name) inherited from a super-class. Recompilation of a client class may be terminated with the message: reference to variable is ambiguous.";
                            }
                        }
                        elsif($Kind eq "Interface_Removed_Super_Interface"
                        or $Kind eq "Class_Removed_Super_Interface")
                        {
                            $Change = "Removed super-interface <b>".htmlSpecChars($Target)."</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoSuchMethodError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find method in $Type_Type <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Interface_Removed_Super_Constant_Interface")
                        {# Source Only
                            $Change = "Removed super-interface <b>".htmlSpecChars($Target)."</b> containing constants only.";
                            $Effect = "Recompilation of a client program may be terminated with the message: cannot find variable in $Type_Type <b>$TypeName</b>.";
                        }
                        elsif($Kind eq "Added_Super_Class")
                        {
                            $Change = "Added super-class <b>".htmlSpecChars($Target)."</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A static field from a super-interface of a client class may hide a field (with the same name) inherited from new super-class and cause <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Effect = "A static field from a super-interface of a client class may hide a field (with the same name) inherited from new super-class. Recompilation of a client class may be terminated with the message: reference to variable is ambiguous.";
                            }
                        }
                        elsif($Kind eq "Abstract_Class_Added_Super_Abstract_Class")
                        {
                            $Change = "Added abstract super-class <b>".htmlSpecChars($Target)."</b>.";
                            if($Level eq "Binary")
                            {
                                if($Add_Effect) {
                                    $Effect = "If abstract methods from an added super-class must be implemented by client then it may be interrupted by <b>AbstractMethodError</b> exception.".$Add_Effect;
                                }
                                else {
                                    $Effect = "No effect.";
                                }
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: a client class C is not abstract and does not override abstract method in <b>$Target</b>.";
                            }
                        }
                        elsif($Kind eq "Removed_Super_Class")
                        {
                            $Change = "Removed super-class <b>".htmlSpecChars($Target)."</b>.";
                            if($Level eq "Binary") {
                                $Effect = "Access of a client program to the fields or methods of the old super-class may be interrupted by <b>NoSuchFieldError</b> or <b>NoSuchMethodError</b> exceptions.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find variable (or method) in <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Changed_Super_Class")
                        {
                            $Change = "Superclass has been changed from <b>".htmlSpecChars($Old_Value)."</b> to <b>".htmlSpecChars($New_Value)."</b>.";
                            if($Level eq "Binary") {
                                $Effect = "1) Access of a client program to the fields or methods of the old super-class may be interrupted by <b>NoSuchFieldError</b> or <b>NoSuchMethodError</b> exceptions.<br/>2) A static field from a super-interface of a client class may hide a field (with the same name) inherited from new super-class and cause <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Effect = "1) Recompilation of a client program may be terminated with the message: cannot find variable (or method) in <b>$TypeName</b>.<br/>2) A static field from a super-interface of a client class may hide a field (with the same name) inherited from new super-class. Recompilation of a client class may be terminated with the message: reference to variable is ambiguous.";
                            }
                        }
                        elsif($Kind eq "Class_Added_Field")
                        {
                            $Change = "Field <b>$Target</b> has been added to this class.";
                            if($Level eq "Binary") {
                                $Effect = "No effect.<br/><b>NOTE</b>: A static field from a super-interface of a client class may hide an added field (with the same name) inherited from the super-class of a client class and cause <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Effect = "No effect.<br/><b>NOTE</b>: A static field from a super-interface of a client class may hide an added field (with the same name) inherited from the super-class of a client class. Recompilation of a client class may be terminated with the message: reference to <b>$Target</b> is ambiguous.";
                            }
                        }
                        elsif($Kind eq "Interface_Added_Field")
                        {
                            $Change = "Field <b>$Target</b> has been added to this interface.";
                            if($Level eq "Binary") {
                                $Effect = "No effect.<br/><b>NOTE</b>: An added static field from a super-interface of a client class may hide a field (with the same name) inherited from the super-class of a client class and cause <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Effect = "No effect.<br/><b>NOTE</b>: An added static field from a super-interface of a client class may hide a field (with the same name) inherited from the super-class of a client class. Recompilation of a client class may be terminated with the message: reference to <b>$Target</b> is ambiguous.";
                            }
                        }
                        elsif($Kind eq "Renamed_Field")
                        {
                            $Change = "Field <b>$Target</b> has been renamed to <b>".htmlSpecChars($New_Value)."</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoSuchFieldError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find variable <b>$Target</b> in <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Renamed_Constant_Field")
                        {
                            if($Level eq "Binary") {
                                $Change = "Field <b>$Target</b> ($Field_Type) with the compile-time constant value <b>$Field_Value</b> has been renamed to <b>".htmlSpecChars($New_Value)."</b>.";
                                $Effect = "A client program may change behavior.";
                            }
                            else {
                                $Change = "Field <b>$Target</b> has been renamed to <b>".htmlSpecChars($New_Value)."</b>.";
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find variable <b>$Target</b> in <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Removed_NonConstant_Field")
                        {
                            $Change = "Field <b>$Target</b> ($Field_Type) has been removed from this $Type_Type.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoSuchFieldError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find variable <b>$Target</b> in <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Removed_Constant_Field")
                        {
                            $Change = "Field <b>$Target</b> ($Field_Type) with the compile-time constant value <b>$Field_Value</b> has been removed from this $Type_Type.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may change behavior.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find variable <b>$Target</b> in <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Changed_Field_Type")
                        {
                            $Change = "Type of field <b>$Target</b> has been changed from <span class='nowrap'><b>".htmlSpecChars($Old_Value)."</b></span> to <span class='nowrap'><b>".htmlSpecChars($New_Value)."</b></span>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoSuchFieldError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: incompatible types, found: <b>$Old_Value</b>, required: <b>$New_Value</b>.";
                            }
                        }
                        elsif($Kind eq "Changed_Field_Access")
                        {
                            $Change = "Access level of field <b>$Target</b> has been changed from <span class='nowrap'><b>".htmlSpecChars($Old_Value)."</b></span> to <span class='nowrap'><b>".htmlSpecChars($New_Value)."</b></span>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>IllegalAccessError</b> exception.";
                            }
                            else
                            {
                                if($New_Value eq "package-private") {
                                    $Effect = "Recompilation of a client program may be terminated with the message: <b>$Target</b> is not public in <b>$TypeName</b>; cannot be accessed from outside package.";
                                }
                                else {
                                    $Effect = "Recompilation of a client program may be terminated with the message: <b>$Target</b> has <b>$New_Value</b> access in <b>$TypeName</b>.";
                                }
                            }
                        }
                        elsif($Kind eq "Changed_Final_Field_Value")
                        {# Binary Only
                            $Change = "Value of final field <b>$Target</b> (<b>$Field_Type</b>) has been changed from <span class='nowrap'><b>".htmlSpecChars($Old_Value)."</b></span> to <span class='nowrap'><b>".htmlSpecChars($New_Value)."</b></span>.";
                            $Effect = "Old value of the field will be inlined to the client code at compile-time and will be used instead of a new one.";
                        }
                        elsif($Kind eq "Field_Became_Final")
                        {
                            $Change = "Field <b>$Target</b> became <b>final</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>IllegalAccessError</b> exception when attempt to assign new values to the field.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot assign a value to final variable $Target.";
                            }
                        }
                        elsif($Kind eq "Field_Became_NonFinal")
                        {# Binary Only
                            $Change = "Field <b>$Target</b> became <b>non-final</b>.";
                            $Effect = "Old value of the field will be inlined to the client code at compile-time and will be used instead of a new one.";
                        }
                        elsif($Kind eq "NonConstant_Field_Became_Static")
                        {# Binary Only
                            $Change = "Non-final field <b>$Target</b> became <b>static</b>.";
                            $Effect = "A client program may be interrupted by <b>IncompatibleClassChangeError</b> exception.";
                        }
                        elsif($Kind eq "NonConstant_Field_Became_NonStatic")
                        {
                            if($Level eq "Binary") {
                                $Change = "Non-constant field <b>$Target</b> became <b>non-static</b>.";
                                $Effect = "A client program may be interrupted by <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Change = "Field <b>$Target</b> became <b>non-static</b>.";
                                $Effect = "Recompilation of a client program may be terminated with the message: non-static variable <b>$Target</b> cannot be referenced from a static context.";
                            }
                        }
                        elsif($Kind eq "Constant_Field_Became_NonStatic")
                        {# Source Only
                            $Change = "Field <b>$Target</b> became <b>non-static</b>.";
                            $Effect = "Recompilation of a client program may be terminated with the message: non-static variable <b>$Target</b> cannot be referenced from a static context.";
                        }
                        elsif($Kind eq "Class_Became_Interface")
                        {
                            $Change = "This <b>class</b> became <b>interface</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>IncompatibleClassChangeError</b> or <b>InstantiationError</b> exception dependent on the usage of this class.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: <b>$TypeName</b> is abstract; cannot be instantiated.";
                            }
                        }
                        elsif($Kind eq "Interface_Became_Class")
                        {
                            $Change = "This <b>interface</b> became <b>class</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>IncompatibleClassChangeError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: interface expected.";
                            }
                        }
                        elsif($Kind eq "Class_Became_Final")
                        {
                            $Change = "This class became <b>final</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>VerifyError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot inherit from final <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Class_Became_Abstract")
                        {
                            $Change = "This class became <b>abstract</b>.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>InstantiationError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: <b>$TypeName</b> is abstract; cannot be instantiated.";
                            }
                        }
                        elsif($Kind eq "Removed_Class")
                        {
                            $Change = "This class has been removed.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoClassDefFoundError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find class <b>$TypeName</b>.";
                            }
                        }
                        elsif($Kind eq "Removed_Interface")
                        {
                            $Change = "This interface has been removed.";
                            if($Level eq "Binary") {
                                $Effect = "A client program may be interrupted by <b>NoClassDefFoundError</b> exception.";
                            }
                            else {
                                $Effect = "Recompilation of a client program may be terminated with the message: cannot find class <b>$TypeName</b>.";
                            }
                        }
                        if($Change)
                        {
                            $TypeProblemsReport .= "<tr><th align='center' valign='top'>$ProblemNum</th><td align='left' valign='top'>".$Change."</td><td align='left' valign='top'>".$Effect."</td></tr>\n";
                            $ProblemNum += 1;
                            $Problems_Number += 1;
                            $Kinds_Locations{$Kind}{$Location} = 1;
                        }
                    }
                }
                $ProblemNum -= 1;
                if($TypeProblemsReport)
                {
                    my $Affected = getAffectedMethods($TypeName, \%Kinds_Locations, $Level);
                    $NAMESPACE_REPORT .= $ContentSpanStart."<span class='extension'>[+]</span> ".htmlSpecChars($TypeName)." ($ProblemNum)".$ContentSpanEnd."<br/>\n";
                    $NAMESPACE_REPORT .= $ContentDivStart."<table class='ptable'><tr>";
                    $NAMESPACE_REPORT .= "<th width='2%'></th><th width='47%'>Change</th><th>Effect</th>";
                    $NAMESPACE_REPORT .= "</tr>$TypeProblemsReport</table>".$Affected."<br/><br/>$ContentDivEnd\n";
                    $NAMESPACE_REPORT = insertIDs($NAMESPACE_REPORT);
                    if($NameSpace) {
                        $NAMESPACE_REPORT=~s/(\W|\A)\Q$NameSpace\E\.(\w)/$1$2/g;
                    }
                }
            }
            if($NAMESPACE_REPORT)
            {
                if($NameSpace) {
                    $NAMESPACE_REPORT = "<span class='package_title'>package</span> <span class='package'>".$NameSpace."</span><br/>\n".$NAMESPACE_REPORT
                }
                if($HEADER_REPORT) {
                    $NAMESPACE_REPORT = "<br/>".$NAMESPACE_REPORT;
                }
                $HEADER_REPORT .= $NAMESPACE_REPORT;
            }
        }
        if($HEADER_REPORT) {
            $TYPE_PROBLEMS .= "<span class='jar'>$ArchiveName</span><br/>\n".$HEADER_REPORT."<br/>";
        }
    }
    if($TYPE_PROBLEMS)
    {
        my $Title = "Problems with Data Types, $TargetSeverity Severity";
        if($TargetSeverity eq "Safe")
        { # Safe Changes
            $Title = "Other Changes in Data Types";
        }
        $TYPE_PROBLEMS = "<a name='".get_Anchor("Type", $Level, $TargetSeverity)."'></a>\n<h2>$Title ($Problems_Number)</h2><hr/>\n".$TYPE_PROBLEMS.$TOP_REF."<br/>\n";
    }
    return $TYPE_PROBLEMS;
}

sub getAffectedMethods($$$)
{
    my ($Target_TypeName, $Kinds_Locations, $Level) = @_;
    my ($Affected, %INumber) = ();
    my $LIMIT = $ShortMode?10:1000;
    foreach my $Method (sort {lc($tr_name{$a}) cmp lc($tr_name{$b})} keys(%CompatProblems))
    {
        last if(keys(%INumber)>$LIMIT);
        my $Signature = $MethodInfo{1}{$Method}{"Signature"};
        foreach my $Kind (keys(%{$CompatProblems{$Method}}))
        {
            foreach my $Location (keys(%{$CompatProblems{$Method}{$Kind}}))
            {
                next if(not $Kinds_Locations->{$Kind}{$Location});
                next if(defined $INumber{$Method});
                my $Type_Name = $CompatProblems{$Method}{$Kind}{$Location}{"Type_Name"};
                next if($Type_Name ne $Target_TypeName);
                $INumber{$Method}=1;
                my $Param_Pos = $CompatProblems{$Method}{$Kind}{$Location}{"Parameter_Position"};
                my $Description = getAffectDescription($Method, $Kind, $Location, $Level);
                $Affected .=  "<span class='nblack'>".highLight_Signature_PPos_Italic($Signature, $Param_Pos, 1, 0)."</span><br/>"."<div class='affect'>".$Description."</div>\n";
            }
        }
    }
    $Affected = "<div class='affected'>".$Affected."</div>";
    if(keys(%INumber)>$LIMIT) {
        $Affected .= "and others ...<br/>";
    }
    if($Affected)
    {
        $Affected =  $ContentDivStart.$Affected.$ContentDivEnd;
        $Affected =  $ContentSpanStart_Affected."[+] affected methods (".(keys(%INumber)>$LIMIT?"more than $LIMIT":keys(%INumber).")").$ContentSpanEnd.$Affected;
    }
    return ($Affected);
}

sub getAffectDescription($$$$)
{
    my ($Method, $Kind, $Location, $Level) = @_;
    my %Affect = %{$CompatProblems{$Method}{$Kind}{$Location}};
    my $Signature = $MethodInfo{1}{$Method}{"Signature"};
    my $Old_Value = $Affect{"Old_Value"};
    my $New_Value = $Affect{"New_Value"};
    my $Type_Name = $Affect{"Type_Name"};
    my $Parameter_Name = $Affect{"Parameter_Name"};
    my $Start_Type_Name = $Affect{"Start_Type_Name"};
    my $Parameter_Position_Str = showPos($Affect{"Parameter_Position"});
    my @Sentence_Parts = ();
    my $Location_To_Type = $Location;
    $Location_To_Type=~s/\.[^.]+?\Z//;
    my %TypeAttr = get_Type($MethodInfo{1}{$Method}{"Class"}, 1);
    my $Type_Type = $TypeAttr{"Type"};
    my $ABSTRACT_M = $MethodInfo{1}{$Method}{"Abstract"}?" abstract":"";
    my $ABSTRACT_C = $TypeAttr{"Abstract"}?" abstract":"";
    my $METHOD_TYPE = $MethodInfo{1}{$Method}{"Constructor"}?"constructor":"method";
    if($Kind eq "Class_Overridden_Method" or $Kind eq "Class_Method_Moved_Up_Hierarchy") {
        return "Method '".highLight_Signature($New_Value)."' will be called instead of this method in a client program.";
    }
    elsif($TypeProblems_Kind{$Level}{$Kind})
    {
        if($Location_To_Type eq "this") {
            return "This$ABSTRACT_M $METHOD_TYPE is from \'$Type_Name\'$ABSTRACT_C $Type_Type.";
        }
        if($Location_To_Type=~/RetVal/)
        {# return value
            if($Location_To_Type=~/\./) {
                push(@Sentence_Parts, "Field \'".htmlSpecChars($Location_To_Type)."\' in return value");
            }
            else {
                push(@Sentence_Parts, "Return value");
            }
        }
        elsif($Location_To_Type=~/this/)
        {# "this" reference
            push(@Sentence_Parts, "Field \'".htmlSpecChars($Location_To_Type)."\' in the object");
        }
        else
        {# parameters
            if($Location_To_Type=~/\./) {
                push(@Sentence_Parts, "Field \'".htmlSpecChars($Location_To_Type)."\' in $Parameter_Position_Str parameter");
            }
            else {
                push(@Sentence_Parts, "$Parameter_Position_Str parameter");
            }
            if($Parameter_Name) {
                push(@Sentence_Parts, "\'$Parameter_Name\'");
            }
        }
        push(@Sentence_Parts, " of this$ABSTRACT_M method");
        if($Start_Type_Name eq $Type_Name) {
            push(@Sentence_Parts, "has type \'".htmlSpecChars($Type_Name)."\'.");
        }
        else {
            push(@Sentence_Parts, "has base type \'".htmlSpecChars($Type_Name)."\'.");
        }
    }
    return join(" ", @Sentence_Parts);
}

sub writeReport($$)
{
    my ($Level, $Report) = @_;
    my $RPath = getReportPath($Level);
    writeFile($RPath, $Report);
    if($Browse)
    {
        system($Browse." $RPath >/dev/null 2>&1 &");
        if($JoinReport or $DoubleReport)
        {
            if($Level eq "Binary")
            { # wait to open a browser
                sleep(1);
            }
        }
    }
}

sub createReport()
{
    if($JoinReport)
    { # --stdout
        writeReport("Join", getReport("Join"));
    }
    elsif($DoubleReport)
    { # default
        writeReport("Binary", getReport("Binary"));
        writeReport("Source", getReport("Source"));
    }
    elsif($BinaryOnly)
    { # --binary
        writeReport("Binary", getReport("Binary"));
    }
    elsif($SourceOnly)
    { # --source
        writeReport("Source", getReport("Source"));
    }
}

sub getReport($)
{
    my $Level = $_[0];
    my $CssStyles = "
    body {
        font-family:Arial, sans-serif;
        color:Black;
        font-size:14px;
    }
    hr {
        color:Black;
        background-color:Black;
        height:1px;
        border:0;
    }
    h1 {
        margin-bottom:0px;
        padding-bottom:0px;
        font-size:26px;
    }
    h2 {
        margin-bottom:0px;
        padding-bottom:0px;
        font-size:20px;
        white-space:nowrap;
    }
    span.section {
        font-weight:bold;
        cursor:pointer;
        font-size:16px;
        color:#003E69;
        white-space:nowrap;
        margin-left:5px;
    }
    span:hover.section {
        color:#336699;
    }
    span.section_affected {
        cursor:pointer;
        margin-left:7px;
        padding-left:15px;
        font-size:14px;
        color:#cc3300;
    }
    span.extension {
        font-weight:100;
        font-size:16px;
    }
    span.jar {
        color:#cc3300;
        font-size:14px;
        font-weight:bold;
    }
    div.class_list {
        padding-left:5px;
        font-size:15px;
    }
    div.jar_list {
        padding-left:5px;
        font-size:15px;
    }
    span.package_title {
        color:#408080;
        font-size:14px;
    }
    span.package_list {
        font-size:14px;
    }
    span.package {
        color:#408080;
        font-size:14px;
        font-weight:bold;
    }
    span.cname {
        color:Green;
        font-size:14px;
        font-weight:bold;
    }
    span.nblack {
        font-weight:bold;
        font-size:15px;
    }
    span.sym_p {
        font-weight:normal;
        white-space:normal;
    }
    span.sym_kind {
        color:Black;
        font-weight:normal;
    }
    div.affect {
        padding-left:15px;
        padding-bottom:4px;
        font-size:14px;
        font-style:italic;
        line-height:13px;
    }
    div.affected {
        padding-left:30px;
        padding-top:3px;
    }
    table.ptable {
        border-collapse:collapse;
        border:1px outset black;
        line-height:16px;
        margin-left:15px;
        margin-top:3px;
        margin-bottom:3px;
        width:900px;
    }
    table.ptable td {
        border:1px solid Gray;
        padding: 3px;
    }
    table.ptable th {
        background-color:#eeeeee;
        font-weight:bold;
        font-size:13px;
        font-family:Verdana;
        border:1px solid Gray;
        text-align:center;
        vertical-align:top;
        white-space:nowrap;
        padding: 3px;
    }
    td.code_line {
        padding-left:15px;
        text-align:left;
        white-space:nowrap;
    }
    table.code_view {
        cursor:text;
        margin-top:7px;
        width:50%;
        margin-left:20px;
        font-family:Consolas, 'DejaVu Sans Mono', 'Droid Sans Mono', Monaco, Monospace;
        font-size:14px;
        padding:10px;
        border:1px solid #e0e8e5;
        color:#444444;
        background-color:#eff3f2;
        overflow:auto;
    }
    table.summary {
        border-collapse:collapse;
        border:1px outset black;
    }
    table.summary th {
        background-color:#eeeeee;
        font-weight:100;
        text-align:left;
        font-size:15px;
        white-space:nowrap;
        border:1px inset gray;
    }
    table.summary td {
        padding-left:10px;
        padding-right:5px;
        text-align:right;
        font-size:16px;
        white-space:nowrap;
        border:1px inset gray;
    }
    span.mangled {
        padding-left:15px;
        font-size:14px;
        cursor:text;
    }
    span.color_p {
        font-style:italic;
        color:Brown;
    }
    span.param {
        font-style:italic;
    }
    span.focus_p {
        font-style:italic;
        color:Red;
    }
    span.nowrap {
        white-space:nowrap;
    }
    td.passed {
        background-color:#CCFFCC;
    }
    td.warning {
        background-color:#F4F4AF;
    }
    td.failed {
        background-color:#FFC3CE;
    }
    td.new {
        background-color:#C6DEFF;
    }";
    
    my $JScripts = "
    function showContent(header, id)
    {
        e = document.getElementById(id);
        if(e.style.display == 'none')
        {
            e.style.display = 'block';
            e.style.visibility = 'visible';
            header.innerHTML = header.innerHTML.replace(/\\\[[^0-9 ]\\\]/gi,\"[&minus;]\");
        }
        else
        {
            e.style.display = 'none';
            e.style.visibility = 'hidden';
            header.innerHTML = header.innerHTML.replace(/\\\[[^0-9 ]\\\]/gi,\"[+]\");
        }
    }";
    if($JoinReport)
    {
        $CssStyles .= "
    .tabset {
        float:left;
    }
    a.tab {
        border:1px solid #AAA;
        float:left;
        margin:0px 5px -1px 0px;
        padding:3px 5px 3px 5px;
        position:relative;
        font-size:14px;
        background-color:#DDD;
        text-decoration:none;
        color:Black;
    }
    a.disabled:hover
    {
        color:Black;
        background:#EEE;
    }
    a.active:hover
    {
        color:Black;
        background:White;
    }
    a.active {
        border-bottom-color:White;
        background-color:White;
    }
    div.tab {
        border:1px solid #AAA;
        padding:0 7px 0 12px;
        width:97%;
        clear:both;
    }";
        $JScripts .= "
    function initTabs()
    {
        var url = window.location.href;
        if(url.indexOf('_Source_')!=-1 || url.indexOf('#Source')!=-1)
        {
            var tab1 = document.getElementById('BinaryID');
            var tab2 = document.getElementById('SourceID');
            tab1.className='tab disabled';
            tab2.className='tab active';
        }
        var sets = document.getElementsByTagName('div');
        for (var i = 0; i < sets.length; i++)
        {
            if (sets[i].className.indexOf('tabset') != -1)
            {
                var tabs = [];
                var links = sets[i].getElementsByTagName('a');
                for (var j = 0; j < links.length; j++)
                {
                    if (links[j].className.indexOf('tab') != -1)
                    {
                        tabs.push(links[j]);
                        links[j].tabs = tabs;
                        var tab = document.getElementById(links[j].href.substr(links[j].href.indexOf('#') + 1));
                        //reset all tabs on start
                        if (tab)
                        {
                            if (links[j].className.indexOf('active')!=-1) {
                                tab.style.display = 'block';
                            }
                            else {
                                tab.style.display = 'none';
                            }
                        }
                        links[j].onclick = function()
                        {
                            var tab = document.getElementById(this.href.substr(this.href.indexOf('#') + 1));
                            if (tab)
                            {
                                //reset all tabs before change
                                for (var k = 0; k < this.tabs.length; k++)
                                {
                                    document.getElementById(this.tabs[k].href.substr(this.tabs[k].href.indexOf('#') + 1)).style.display = 'none';
                                    this.tabs[k].className = this.tabs[k].className.replace('active', 'disabled');
                                }
                                this.className = 'tab active';
                                tab.style.display = 'block';
                                // window.location.hash = this.id.replace('ID', '');
                                return false;
                            }
                        }
                    }
                }
            }
        }
        if(url.indexOf('#')!=-1) {
            location.href=location.href;
        }
    }
    if (window.addEventListener) window.addEventListener('load', initTabs, false);
    else if (window.attachEvent) window.attachEvent('onload', initTabs);";
    }
    
    if($Level eq "Join")
    {
        my $Title = "$TargetLibraryFullName: ".$Descriptor{1}{"Version"}." to ".$Descriptor{2}{"Version"}." compatibility report";
        my $Keywords = "$TargetLibraryFullName, compatibility";
        my $Description = "Compatibility report for the $TargetLibraryFullName library between ".$Descriptor{1}{"Version"}." and ".$Descriptor{2}{"Version"}." versions";
        my ($BSummary, $BMetaData) = get_Summary("Binary");
        my ($SSummary, $SMetaData) = get_Summary("Source");
        my $Report = "<!-\- $BMetaData -\->\n<!-\- $SMetaData -\->\n".composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."<body><a name='Source'></a><a name='Binary'></a><a name='Top'></a>";
        $Report .= get_Report_Header("Join")."
        <br/><div class='tabset'>
        <a id='BinaryID' href='#BinaryTab' class='tab active'>Binary<br/>Compatibility</a>
        <a id='SourceID' href='#SourceTab' style='margin-left:3px' class='tab disabled'>Source<br/>Compatibility</a>
        </div>";
        $Report .= "<div id='BinaryTab' class='tab'>\n$BSummary\n".get_Report_Added("Binary").get_Report_Removed("Binary").get_Report_Problems("High", "Binary").get_Report_Problems("Medium", "Binary").get_Report_Problems("Low", "Binary").get_Report_Problems("Safe", "Binary").get_SourceInfo()."<br/><br/><br/></div>";
        $Report .= "<div id='SourceTab' class='tab'>\n$SSummary\n".get_Report_Added("Source").get_Report_Removed("Source").get_Report_Problems("High", "Source").get_Report_Problems("Medium", "Source").get_Report_Problems("Low", "Source").get_Report_Problems("Safe", "Source").get_SourceInfo()."<br/><br/><br/></div>";
        $Report .= getReportFooter($TargetLibraryFullName);
        $Report .= "\n<div style='height:999px;'></div>\n</body></html>";
        return $Report;
    }
    else
    {
        my ($Summary, $MetaData) = get_Summary($Level);
        my $Title = "$TargetLibraryFullName: ".$Descriptor{1}{"Version"}." to ".$Descriptor{2}{"Version"}." ".lc($Level)." compatibility report";
        my $Keywords = "$TargetLibraryFullName, ".lc($Level).", compatibility";
        my $Description = "$Level compatibility report for the $TargetLibraryFullName library between ".$Descriptor{1}{"Version"}." and ".$Descriptor{2}{"Version"}." versions";
        
        my $Report = "<!-\- $MetaData -\->\n".composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."<body><a name='Top'></a>";
        $Report .= get_Report_Header($Level)."\n".$Summary."\n";
        $Report .= get_Report_Added($Level).get_Report_Removed($Level);
        $Report .= get_Report_Problems("High", $Level).get_Report_Problems("Medium", $Level).get_Report_Problems("Low", $Level).get_Report_Problems("Safe", $Level);
        $Report .= get_SourceInfo()."<br/><br/><br/><hr/>\n";
        $Report .= getReportFooter($TargetLibraryFullName);
        $Report .= "\n<div style='height:999px;'></div>\n</body></html>";
        return $Report;
    }
}


sub getReportFooter($)
{
    my $LibName = $_[0];
    my $FooterStyle = (not $JoinReport)?"width:99%":"width:97%;padding-top:3px";
    my $Footer = "<div style='$FooterStyle;font-size:11px;' align='right'><i>Generated on ".(localtime time); # report date
    $Footer .= " for <span style='font-weight:bold'>$LibName</span>"; # tested library/system name
    $Footer .= " by <a href='".$HomePage{"Wiki"}."'>Java API Compliance Checker</a>"; # tool name
    my $ToolSummary = "<br/>A tool for checking backward compatibility of a Java library API&#160;&#160;";
    $Footer .= " $TOOL_VERSION &#160;$ToolSummary</i></div>"; # tool version
    return $Footer;
}

sub get_Report_Problems($$)
{
    my ($Priority, $Level) = @_;
    my $Report = get_Report_TypeProblems($Priority, $Level);
    if(my $MProblems = get_Report_MethodProblems($Priority, $Level)) {
        $Report .= $MProblems;
    }
    if($Priority eq "Low")
    {
        if($CheckImpl and $Level eq "Binary") {
            $Report .= get_Report_Implementation();
        }
    }
    if($Report)
    {
        if($JoinReport)
        {
            if($Priority eq "Safe") {
                $Report = "<a name=\'Other_".$Level."_Changes\'></a>".$Report;
            }
            else {
                $Report = "<a name=\'".$Priority."_Risk_".$Level."_Problems\'></a>".$Report;
            }
        }
        else
        {
            if($Priority eq "Safe") {
                $Report = "<a name=\'Other_Changes\'></a>".$Report;
            }
            else {
                $Report = "<a name=\'".$Priority."_Risk_Problems\'></a>".$Report;
            }
        }
    }
    return $Report;
}

sub composeHTML_Head($$$$$)
{
    my ($Title, $Keywords, $Description, $Styles, $Scripts) = @_;
    return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
    <html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">
    <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
    <meta name=\"keywords\" content=\"$Keywords\" />
    <meta name=\"description\" content=\"$Description\" />
    <title>
        $Title
    </title>
    <style type=\"text/css\">
    $Styles
    </style>
    <script type=\"text/javascript\" language=\"JavaScript\">
    <!--
    $Scripts
    -->
    </script>
    </head>";
}

sub insertIDs($)
{
    my $Text = $_[0];
    while($Text=~/CONTENT_ID/)
    {
        if(int($Content_Counter)%2)
        {
            $ContentID -= 1;
        }
        $Text=~s/CONTENT_ID/c_$ContentID/;
        $ContentID += 1;
        $Content_Counter += 1;
    }
    return $Text;
}

sub readArchives($)
{
    my $LibVersion = $_[0];
    my @ArchivePaths = getArchives($LibVersion);
    if($#ArchivePaths==-1) {
        exitStatus("Error", "Java ARchives are not found in ".$Descriptor{$LibVersion}{"Version"});
    }
    print "reading classes ".$Descriptor{$LibVersion}{"Version"}." ...\n";
    $TypeID = 0;
    foreach my $ArchivePath (sort {length($a)<=>length($b)} @ArchivePaths) {
        readArchive($LibVersion, $ArchivePath);
    }
    foreach my $TName (keys(%{$TName_Tid{$LibVersion}}))
    {
        my $Tid = $TName_Tid{$LibVersion}{$TName};
        if(not $TypeInfo{$LibVersion}{$Tid}{"Type"})
        {
            if($TName=~/\A(void|boolean|char|byte|short|int|float|long|double)\Z/) {
                $TypeInfo{$LibVersion}{$Tid}{"Type"} = "primitive";
            }
            else {
                $TypeInfo{$LibVersion}{$Tid}{"Type"} = "class";
            }
        }
    }
    foreach my $Method (keys(%{$MethodInfo{$LibVersion}}))
    {
        $MethodInfo{$LibVersion}{$Method}{"Signature"} = get_Signature($Method, $LibVersion, "Full");
        $tr_name{$Method} = get_TypeName($MethodInfo{$LibVersion}{$Method}{"Class"}, $LibVersion).".".get_Signature($Method, $LibVersion, "Short");
    }
}

sub testSystem()
{
    print "\nverifying detectable Java library changes\n";
    my $LibName = "libsample_java";
    rmtree($LibName);
    my $PackageName = "TestPackage";
    my $Path_v1 = "$LibName/$PackageName.v1/$PackageName";
    mkpath($Path_v1);
    my $Path_v2 = "$LibName/$PackageName.v2/$PackageName";
    mkpath($Path_v2);
    my $TestsPath = "$LibName/Tests";
    mkpath($TestsPath);
    
    # FirstCheckedException
    my $FirstCheckedException = "package $PackageName;
    public class FirstCheckedException extends Exception {
    }";
    writeFile($Path_v1."/FirstCheckedException.java", $FirstCheckedException);
    writeFile($Path_v2."/FirstCheckedException.java", $FirstCheckedException);
    
    # SecondCheckedException
    my $SecondCheckedException = "package $PackageName;
    public class SecondCheckedException extends Exception {
    }";
    writeFile($Path_v1."/SecondCheckedException.java", $SecondCheckedException);
    writeFile($Path_v2."/SecondCheckedException.java", $SecondCheckedException);
    
    # FirstUncheckedException
    my $FirstUncheckedException = "package $PackageName;
    public class FirstUncheckedException extends RuntimeException {
    }";
    writeFile($Path_v1."/FirstUncheckedException.java", $FirstUncheckedException);
    writeFile($Path_v2."/FirstUncheckedException.java", $FirstUncheckedException);
    
    # SecondUncheckedException
    my $SecondUncheckedException = "package $PackageName;
    public class SecondUncheckedException extends RuntimeException {
    }";
    writeFile($Path_v1."/SecondUncheckedException.java", $SecondUncheckedException);
    writeFile($Path_v2."/SecondUncheckedException.java", $SecondUncheckedException);
    
    # BaseAbstractClass
    my $BaseAbstractClass = "package $PackageName;
    public abstract class BaseAbstractClass {
        public Integer field;
        public Integer someMethod(Integer param) { return param; }
        public abstract Integer abstractMethod(Integer param);
    }";
    writeFile($Path_v1."/BaseAbstractClass.java", $BaseAbstractClass);
    writeFile($Path_v2."/BaseAbstractClass.java", $BaseAbstractClass);
    
    # BaseClass
    my $BaseClass = "package $PackageName;
    public class BaseClass {
        public Integer field;
        public Integer method(Integer param) { return param; }
    }";
    writeFile($Path_v1."/BaseClass.java", $BaseClass);
    writeFile($Path_v2."/BaseClass.java", $BaseClass);
    
    # BaseClass2
    my $BaseClass2 = "package $PackageName;
    public class BaseClass2 {
        public Integer field2;
        public Integer method2(Integer param) { return param; }
    }";
    writeFile($Path_v1."/BaseClass2.java", $BaseClass2);
    writeFile($Path_v2."/BaseClass2.java", $BaseClass2);
    
    # BaseInterface
    my $BaseInterface = "package $PackageName;
    public interface BaseInterface {
        public Integer field = 100;
        public Integer method(Integer param);
    }";
    writeFile($Path_v1."/BaseInterface.java", $BaseInterface);
    writeFile($Path_v2."/BaseInterface.java", $BaseInterface);
    
    # BaseInterface2
    my $BaseInterface2 = "package $PackageName;
    public interface BaseInterface2 {
        public Integer field2 = 100;
        public Integer method2(Integer param);
    }";
    writeFile($Path_v1."/BaseInterface2.java", $BaseInterface2);
    writeFile($Path_v2."/BaseInterface2.java", $BaseInterface2);
    
    # BaseConstantInterface
    my $BaseConstantInterface = "package $PackageName;
    public interface BaseConstantInterface {
        public Integer CONSTANT = 10;
        public Integer CONSTANT2 = 100;
    }";
    writeFile($Path_v1."/BaseConstantInterface.java", $BaseConstantInterface);
    writeFile($Path_v2."/BaseConstantInterface.java", $BaseConstantInterface);
    
    # Abstract_Method_Added_Checked_Exception
    writeFile($Path_v1."/AbstractMethodAddedCheckedException.java",
    "package $PackageName;
    public abstract class AbstractMethodAddedCheckedException {
        public abstract Integer someMethod() throws FirstCheckedException;
    }");
    writeFile($Path_v2."/AbstractMethodAddedCheckedException.java",
    "package $PackageName;
    public abstract class AbstractMethodAddedCheckedException {
        public abstract Integer someMethod() throws FirstCheckedException, SecondCheckedException;
    }");
    
    # Abstract_Method_Removed_Checked_Exception
    writeFile($Path_v1."/AbstractMethodRemovedCheckedException.java",
    "package $PackageName;
    public abstract class AbstractMethodRemovedCheckedException {
        public abstract Integer someMethod() throws FirstCheckedException, SecondCheckedException;
    }");
    writeFile($Path_v2."/AbstractMethodRemovedCheckedException.java",
    "package $PackageName;
    public abstract class AbstractMethodRemovedCheckedException {
        public abstract Integer someMethod() throws FirstCheckedException;
    }");
    
    # NonAbstract_Method_Added_Checked_Exception
    writeFile($Path_v1."/NonAbstractMethodAddedCheckedException.java",
    "package $PackageName;
    public class NonAbstractMethodAddedCheckedException {
        public Integer someMethod() throws FirstCheckedException {
            return 10;
        }
    }");
    writeFile($Path_v2."/NonAbstractMethodAddedCheckedException.java",
    "package $PackageName;
    public class NonAbstractMethodAddedCheckedException {
        public Integer someMethod() throws FirstCheckedException, SecondCheckedException {
            return 10;
        }
    }");
    
    # NonAbstract_Method_Removed_Checked_Exception
    writeFile($Path_v1."/NonAbstractMethodRemovedCheckedException.java",
    "package $PackageName;
    public class NonAbstractMethodRemovedCheckedException {
        public Integer someMethod() throws FirstCheckedException, SecondCheckedException {
            return 10;
        }
    }");
    writeFile($Path_v2."/NonAbstractMethodRemovedCheckedException.java",
    "package $PackageName;
    public class NonAbstractMethodRemovedCheckedException {
        public Integer someMethod() throws FirstCheckedException {
            return 10;
        }
    }");
    
    # Added_Unchecked_Exception
    writeFile($Path_v1."/AddedUncheckedException.java",
    "package $PackageName;
    public class AddedUncheckedException {
        public Integer someMethod() throws FirstUncheckedException {
            return 10;
        }
    }");
    writeFile($Path_v2."/AddedUncheckedException.java",
    "package $PackageName;
    public class AddedUncheckedException {
        public Integer someMethod() throws FirstUncheckedException, SecondUncheckedException, NullPointerException {
            return 10;
        }
    }");
    
    # Removed_Unchecked_Exception
    writeFile($Path_v1."/RemovedUncheckedException.java",
    "package $PackageName;
    public class RemovedUncheckedException {
        public Integer someMethod() throws FirstUncheckedException, SecondUncheckedException, NullPointerException {
            return 10;
        }
    }");
    writeFile($Path_v2."/RemovedUncheckedException.java",
    "package $PackageName;
    public class RemovedUncheckedException {
        public Integer someMethod() throws FirstUncheckedException {
            return 10;
        }
    }");
    
    # Changed_Method_Return_From_Void
    writeFile($Path_v1."/ChangedMethodReturnFromVoid.java",
    "package $PackageName;
    public class ChangedMethodReturnFromVoid {
        public void changedMethod(Integer param1, String[] param2) { }
    }");
    writeFile($Path_v2."/ChangedMethodReturnFromVoid.java",
    "package $PackageName;
    public class ChangedMethodReturnFromVoid {
        public Integer changedMethod(Integer param1, String[] param2){
            return param1;
        }
    }");
    
    # Added_Method
    writeFile($Path_v1."/AddedMethod.java",
    "package $PackageName;
    public class AddedMethod {
        public Integer field = 100;
    }");
    writeFile($Path_v2."/AddedMethod.java",
    "package $PackageName;
    public class AddedMethod {
        public Integer field = 100;
        public Integer addedMethod(Integer param1, String[] param2) { return param1; }
        public static String[] addedStaticMethod(String[] param) { return param; }
    }");
    
    # Added_Method (Constructor)
    writeFile($Path_v1."/AddedConstructor.java",
    "package $PackageName;
    public class AddedConstructor {
        public Integer field = 100;
    }");
    writeFile($Path_v2."/AddedConstructor.java",
    "package $PackageName;
    public class AddedConstructor {
        public Integer field = 100;
        public AddedConstructor() { }
        public AddedConstructor(Integer x, String y) { }
    }");
    
    # Class_Added_Field
    writeFile($Path_v1."/ClassAddedField.java",
    "package $PackageName;
    public class ClassAddedField {
        public Integer otherField;
    }");
    writeFile($Path_v2."/ClassAddedField.java",
    "package $PackageName;
    public class ClassAddedField {
        public Integer addedField;
        public Integer otherField;
    }");
    
    # Interface_Added_Field
    writeFile($Path_v1."/InterfaceAddedField.java",
    "package $PackageName;
    public interface InterfaceAddedField {
        public Integer method();
    }");
    writeFile($Path_v2."/InterfaceAddedField.java",
    "package $PackageName;
    public interface InterfaceAddedField {
        public Integer addedField = 100;
        public Integer method();
    }");
    
    # Removed_NonConstant_Field (Class)
    writeFile($Path_v1."/ClassRemovedField.java",
    "package $PackageName;
    public class ClassRemovedField {
        public Integer removedField;
        public Integer otherField;
    }");
    writeFile($Path_v2."/ClassRemovedField.java",
    "package $PackageName;
    public class ClassRemovedField {
        public Integer otherField;
    }");
    
    writeFile($TestsPath."/Test_ClassRemovedField.java",
    "import $PackageName.*;
    public class Test_ClassRemovedField {
        public static void main(String[] args) {
            ClassRemovedField X = new ClassRemovedField();
            Integer Copy = X.removedField;
        }
    }");
    
    # Removed_Constant_Field (Interface)
    writeFile($Path_v1."/InterfaceRemovedConstantField.java",
    "package $PackageName;
    public interface InterfaceRemovedConstantField {
        public String someMethod();
        public int removedField_Int = 1000;
        public String removedField_Str = \"Value\";
    }");
    writeFile($Path_v2."/InterfaceRemovedConstantField.java",
    "package $PackageName;
    public interface InterfaceRemovedConstantField {
        public String someMethod();
    }");
    
    # Removed_NonConstant_Field (Interface)
    writeFile($Path_v1."/InterfaceRemovedField.java",
    "package $PackageName;
    public interface InterfaceRemovedField {
        public String someMethod();
        public BaseClass removedField = new BaseClass();
    }");
    writeFile($Path_v2."/InterfaceRemovedField.java",
    "package $PackageName;
    public interface InterfaceRemovedField {
        public String someMethod();
    }");
    
    # Renamed_Field
    writeFile($Path_v1."/RenamedField.java",
    "package $PackageName;
    public class RenamedField {
        public String oldName;
    }");
    writeFile($Path_v2."/RenamedField.java",
    "package $PackageName;
    public class RenamedField {
        public String newName;
    }");
    
    # Renamed_Constant_Field
    writeFile($Path_v1."/RenamedConstantField.java",
    "package $PackageName;
    public class RenamedConstantField {
        public final String oldName = \"Value\";
    }");
    writeFile($Path_v2."/RenamedConstantField.java",
    "package $PackageName;
    public class RenamedConstantField {
        public final String newName = \"Value\";
    }");
    
    # Changed_Field_Type
    writeFile($Path_v1."/ChangedFieldType.java",
    "package $PackageName;
    public class ChangedFieldType {
        public String fieldName;
    }");
    writeFile($Path_v2."/ChangedFieldType.java",
    "package $PackageName;
    public class ChangedFieldType {
        public Integer fieldName;
    }");
    
    # Changed_Field_Access
    writeFile($Path_v1."/ChangedFieldAccess.java",
    "package $PackageName;
    public class ChangedFieldAccess {
        public String fieldName;
    }");
    writeFile($Path_v2."/ChangedFieldAccess.java",
    "package $PackageName;
    public class ChangedFieldAccess {
        private String fieldName;
    }");
    
    # Changed_Final_Field_Value
    writeFile($Path_v1."/ChangedFinalFieldValue.java",
    "package $PackageName;
    public class ChangedFinalFieldValue {
        public final int field = 1;
        public final String field2 = \" \";
    }");
    writeFile($Path_v2."/ChangedFinalFieldValue.java",
    "package $PackageName;
    public class ChangedFinalFieldValue {
        public final int field = 2;
        public final String field2 = \"newValue\";
    }");
    
    # NonConstant_Field_Became_Static
    writeFile($Path_v1."/NonConstantFieldBecameStatic.java",
    "package $PackageName;
    public class NonConstantFieldBecameStatic {
        public String fieldName;
    }");
    writeFile($Path_v2."/NonConstantFieldBecameStatic.java",
    "package $PackageName;
    public class NonConstantFieldBecameStatic {
        public static String fieldName;
    }");
    
    # NonConstant_Field_Became_NonStatic
    writeFile($Path_v1."/NonConstantFieldBecameNonStatic.java",
    "package $PackageName;
    public class NonConstantFieldBecameNonStatic {
        public static String fieldName;
    }");
    writeFile($Path_v2."/NonConstantFieldBecameNonStatic.java",
    "package $PackageName;
    public class NonConstantFieldBecameNonStatic {
        public String fieldName;
    }");
    
    # Constant_Field_Became_NonStatic
    writeFile($Path_v1."/ConstantFieldBecameNonStatic.java",
    "package $PackageName;
    public class ConstantFieldBecameNonStatic {
        public final static String fieldName = \"Value\";
    }");
    writeFile($Path_v2."/ConstantFieldBecameNonStatic.java",
    "package $PackageName;
    public class ConstantFieldBecameNonStatic {
        public final String fieldName = \"Value\";
    }");
    
    # Field_Became_Final
    writeFile($Path_v1."/FieldBecameFinal.java",
    "package $PackageName;
    public class FieldBecameFinal {
        public String fieldName;
    }");
    writeFile($Path_v2."/FieldBecameFinal.java",
    "package $PackageName;
    public class FieldBecameFinal {
        public final String fieldName = \"Value\";
    }");
    
    # Field_Became_NonFinal
    writeFile($Path_v1."/FieldBecameNonFinal.java",
    "package $PackageName;
    public class FieldBecameNonFinal {
        public final String fieldName = \"Value\";
    }");
    writeFile($Path_v2."/FieldBecameNonFinal.java",
    "package $PackageName;
    public class FieldBecameNonFinal {
        public String fieldName;
    }");
    
    # Removed_Method
    writeFile($Path_v1."/RemovedMethod.java",
    "package $PackageName;
    public class RemovedMethod {
        public Integer field = 100;
        public Integer removedMethod(Integer param1, String param2) { return param1; }
        public Integer removedStaticMethod(Integer param) { return param; }
    }");
    writeFile($Path_v2."/RemovedMethod.java",
    "package $PackageName;
    public class RemovedMethod {
        public Integer field = 100;
    }");
    
    # Interface_Removed_Abstract_Method
    writeFile($Path_v1."/InterfaceRemovedAbstractMethod.java",
    "package $PackageName;
    public interface InterfaceRemovedAbstractMethod extends BaseInterface, BaseInterface2 {
        public void removedMethod(Integer param1, java.io.ObjectOutput param2);
        public void someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceRemovedAbstractMethod.java",
    "package $PackageName;
    public interface InterfaceRemovedAbstractMethod extends BaseInterface, BaseInterface2 {
        public void someMethod(Integer param);
    }");
    
    # Interface_Added_Abstract_Method
    writeFile($Path_v1."/InterfaceAddedAbstractMethod.java",
    "package $PackageName;
    public interface InterfaceAddedAbstractMethod extends BaseInterface, BaseInterface2 {
        public void someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceAddedAbstractMethod.java",
    "package $PackageName;
    public interface InterfaceAddedAbstractMethod extends BaseInterface, BaseInterface2 {
        public void someMethod(Integer param);
        public Integer addedMethod(Integer param);
    }");
    
    # Variable_Arity_To_Array
    writeFile($Path_v1."/VariableArityToArray.java",
    "package $PackageName;
    public class VariableArityToArray {
        public void someMethod(Integer x, String... y) { };
    }");
    writeFile($Path_v2."/VariableArityToArray.java",
    "package $PackageName;
    public class VariableArityToArray {
        public void someMethod(Integer x, String[] y) { };
    }");
    
    # Class_Became_Interface
    writeFile($Path_v1."/ClassBecameInterface.java",
    "package $PackageName;
    public class ClassBecameInterface extends BaseClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/ClassBecameInterface.java",
    "package $PackageName;
    public interface ClassBecameInterface extends BaseInterface, BaseInterface2 {
        public Integer someMethod(Integer param);
    }");
    
    # Added_Super_Class
    writeFile($Path_v1."/AddedSuperClass.java",
    "package $PackageName;
    public class AddedSuperClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/AddedSuperClass.java",
    "package $PackageName;
    public class AddedSuperClass extends BaseClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    
    # Abstract_Class_Added_Super_Abstract_Class
    writeFile($Path_v1."/AbstractClassAddedSuperAbstractClass.java",
    "package $PackageName;
    public abstract class AbstractClassAddedSuperAbstractClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/AbstractClassAddedSuperAbstractClass.java",
    "package $PackageName;
    public abstract class AbstractClassAddedSuperAbstractClass extends BaseAbstractClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    
    # Removed_Super_Class
    writeFile($Path_v1."/RemovedSuperClass.java",
    "package $PackageName;
    public class RemovedSuperClass extends BaseClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/RemovedSuperClass.java",
    "package $PackageName;
    public class RemovedSuperClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    
    # Changed_Super_Class
    writeFile($Path_v1."/ChangedSuperClass.java",
    "package $PackageName;
    public class ChangedSuperClass extends BaseClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/ChangedSuperClass.java",
    "package $PackageName;
    public class ChangedSuperClass extends BaseClass2 {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    
    # Abstract_Class_Added_Super_Interface
    writeFile($Path_v1."/AbstractClassAddedSuperInterface.java",
    "package $PackageName;
    public abstract class AbstractClassAddedSuperInterface implements BaseInterface {
        public Integer method(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/AbstractClassAddedSuperInterface.java",
    "package $PackageName;
    public abstract class AbstractClassAddedSuperInterface implements BaseInterface, BaseInterface2 {
        public Integer method(Integer param) {
            return param;
        }
    }");
    
    # Class_Removed_Super_Interface
    writeFile($Path_v1."/ClassRemovedSuperInterface.java",
    "package $PackageName;
    public class ClassRemovedSuperInterface implements BaseInterface, BaseInterface2 {
        public Integer method(Integer param) {
            return param;
        }
        public Integer method2(Integer param) {
            return param;
        }
    }");
    writeFile($Path_v2."/ClassRemovedSuperInterface.java",
    "package $PackageName;
    public class ClassRemovedSuperInterface implements BaseInterface {
        public Integer method(Integer param) {
            return param;
        }
        public Integer method2(Integer param) {
            return param;
        }
    }");
    
    # Interface_Added_Super_Interface
    writeFile($Path_v1."/InterfaceAddedSuperInterface.java",
    "package $PackageName;
    public interface InterfaceAddedSuperInterface extends BaseInterface {
        public Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceAddedSuperInterface.java",
    "package $PackageName;
    public interface InterfaceAddedSuperInterface extends BaseInterface, BaseInterface2 {
        public Integer someMethod(Integer param);
    }");
    
    # Interface_Added_Super_Constant_Interface
    writeFile($Path_v1."/InterfaceAddedSuperConstantInterface.java",
    "package $PackageName;
    public interface InterfaceAddedSuperConstantInterface extends BaseInterface {
        public Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceAddedSuperConstantInterface.java",
    "package $PackageName;
    public interface InterfaceAddedSuperConstantInterface extends BaseInterface, BaseConstantInterface {
        public Integer someMethod(Integer param);
    }");
    
    # Interface_Removed_Super_Interface
    writeFile($Path_v1."/InterfaceRemovedSuperInterface.java",
    "package $PackageName;
    public interface InterfaceRemovedSuperInterface extends BaseInterface, BaseInterface2 {
        public Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceRemovedSuperInterface.java",
    "package $PackageName;
    public interface InterfaceRemovedSuperInterface extends BaseInterface {
        public Integer someMethod(Integer param);
    }");
    
    # Interface_Removed_Super_Constant_Interface
    writeFile($Path_v1."/InterfaceRemovedSuperConstantInterface.java",
    "package $PackageName;
    public interface InterfaceRemovedSuperConstantInterface extends BaseInterface, BaseConstantInterface {
        public Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceRemovedSuperConstantInterface.java",
    "package $PackageName;
    public interface InterfaceRemovedSuperConstantInterface extends BaseInterface {
        public Integer someMethod(Integer param);
    }");
    
    # Interface_Became_Class
    writeFile($Path_v1."/InterfaceBecameClass.java",
    "package $PackageName;
    public interface InterfaceBecameClass extends BaseInterface, BaseInterface2 {
        public Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/InterfaceBecameClass.java",
    "package $PackageName;
    public class InterfaceBecameClass extends BaseClass {
        public Integer someMethod(Integer param) {
            return param;
        }
    }");
    
    # Removed_Class
    writeFile($Path_v1."/RemovedClass.java",
    "package $PackageName;
    public class RemovedClass extends BaseClass {
        public Integer someMethod(Integer param){
            return param;
        }
    }");
    
    # Removed_Interface
    writeFile($Path_v1."/RemovedInterface.java",
    "package $PackageName;
    public interface RemovedInterface extends BaseInterface, BaseInterface2 {
        public Integer someMethod(Integer param);
    }");
    
    # NonAbstract_Class_Added_Abstract_Method
    writeFile($Path_v1."/NonAbstractClassAddedAbstractMethod.java",
    "package $PackageName;
    public class NonAbstractClassAddedAbstractMethod {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
    }");
    writeFile($Path_v2."/NonAbstractClassAddedAbstractMethod.java",
    "package $PackageName;
    public abstract class NonAbstractClassAddedAbstractMethod {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public abstract Integer addedMethod(Integer param);
    }");
    
    # Abstract_Class_Added_Abstract_Method
    writeFile($Path_v1."/AbstractClassAddedAbstractMethod.java",
    "package $PackageName;
    public abstract class AbstractClassAddedAbstractMethod {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
    }");
    writeFile($Path_v2."/AbstractClassAddedAbstractMethod.java",
    "package $PackageName;
    public abstract class AbstractClassAddedAbstractMethod {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public abstract Integer addedMethod(Integer param);
    }");
    
    # Class_Became_Abstract
    writeFile($Path_v1."/ClassBecameAbstract.java",
    "package $PackageName;
    public class ClassBecameAbstract {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
    }");
    writeFile($Path_v2."/ClassBecameAbstract.java",
    "package $PackageName;
    public abstract class ClassBecameAbstract {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public abstract Integer addedMethod(Integer param);
    }");
    
    # Class_Became_Final
    writeFile($Path_v1."/ClassBecameFinal.java",
    "package $PackageName;
    public class ClassBecameFinal {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
    }");
    writeFile($Path_v2."/ClassBecameFinal.java",
    "package $PackageName;
    public final class ClassBecameFinal {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
    }");
    
    # Class_Removed_Abstract_Method
    writeFile($Path_v1."/ClassRemovedAbstractMethod.java",
    "package $PackageName;
    public abstract class ClassRemovedAbstractMethod {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public abstract Integer removedMethod(Integer param);
    }");
    writeFile($Path_v2."/ClassRemovedAbstractMethod.java",
    "package $PackageName;
    public abstract class ClassRemovedAbstractMethod {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
    }");
    
    # Class_Method_Became_Abstract
    writeFile($Path_v1."/ClassMethodBecameAbstract.java",
    "package $PackageName;
    public abstract class ClassMethodBecameAbstract {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public Integer someMethod(Integer param){
            return param;
        };
    }");
    writeFile($Path_v2."/ClassMethodBecameAbstract.java",
    "package $PackageName;
    public abstract class ClassMethodBecameAbstract {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public abstract Integer someMethod(Integer param);
    }");
    
    # Class_Method_Became_NonAbstract
    writeFile($Path_v1."/ClassMethodBecameNonAbstract.java",
    "package $PackageName;
    public abstract class ClassMethodBecameNonAbstract {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public abstract Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/ClassMethodBecameNonAbstract.java",
    "package $PackageName;
    public abstract class ClassMethodBecameNonAbstract {
        public Integer someMethod(Integer param1, String[] param2) {
            return param1;
        };
        public Integer someMethod(Integer param){
            return param;
        };
    }");
    
    # Method_Became_Static
    writeFile($Path_v1."/MethodBecameStatic.java",
    "package $PackageName;
    public class MethodBecameStatic {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/MethodBecameStatic.java",
    "package $PackageName;
    public class MethodBecameStatic {
        public static Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Method_Became_NonStatic
    writeFile($Path_v1."/MethodBecameNonStatic.java",
    "package $PackageName;
    public class MethodBecameNonStatic {
        public static Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/MethodBecameNonStatic.java",
    "package $PackageName;
    public class MethodBecameNonStatic {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Static_Method_Became_Final
    writeFile($Path_v1."/StaticMethodBecameFinal.java",
    "package $PackageName;
    public class StaticMethodBecameFinal {
        public static Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/StaticMethodBecameFinal.java",
    "package $PackageName;
    public class StaticMethodBecameFinal {
        public static final Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # NonStatic_Method_Became_Final
    writeFile($Path_v1."/NonStaticMethodBecameFinal.java",
    "package $PackageName;
    public class NonStaticMethodBecameFinal {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/NonStaticMethodBecameFinal.java",
    "package $PackageName;
    public class NonStaticMethodBecameFinal {
        public final Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Method_Became_Abstract
    writeFile($Path_v1."/MethodBecameAbstract.java",
    "package $PackageName;
    public abstract class MethodBecameAbstract {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/MethodBecameAbstract.java",
    "package $PackageName;
    public abstract class MethodBecameAbstract {
        public abstract Integer someMethod(Integer param);
    }");
    
    # Method_Became_NonAbstract
    writeFile($Path_v1."/MethodBecameNonAbstract.java",
    "package $PackageName;
    public abstract class MethodBecameNonAbstract {
        public abstract Integer someMethod(Integer param);
    }");
    writeFile($Path_v2."/MethodBecameNonAbstract.java",
    "package $PackageName;
    public abstract class MethodBecameNonAbstract {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Changed_Method_Access
    writeFile($Path_v1."/ChangedMethodAccess.java",
    "package $PackageName;
    public class ChangedMethodAccess {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/ChangedMethodAccess.java",
    "package $PackageName;
    public class ChangedMethodAccess {
        protected Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Method_Became_Synchronized
    writeFile($Path_v1."/MethodBecameSynchronized.java",
    "package $PackageName;
    public class MethodBecameSynchronized {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/MethodBecameSynchronized.java",
    "package $PackageName;
    public class MethodBecameSynchronized {
        public synchronized Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Method_Became_NonSynchronized
    writeFile($Path_v1."/MethodBecameNonSynchronized.java",
    "package $PackageName;
    public class MethodBecameNonSynchronized {
        public synchronized Integer someMethod(Integer param) {
            return param;
        };
    }");
    writeFile($Path_v2."/MethodBecameNonSynchronized.java",
    "package $PackageName;
    public class MethodBecameNonSynchronized {
        public Integer someMethod(Integer param) {
            return param;
        };
    }");
    
    # Class_Overridden_Method
    writeFile($Path_v1."/OverriddenMethod.java",
    "package $PackageName;
    public class OverriddenMethod extends BaseClass {
        public Integer someMethod(Integer param) { return param; }
    }");
    writeFile($Path_v2."/OverriddenMethod.java",
    "package $PackageName;
    public class OverriddenMethod extends BaseClass {
        public Integer someMethod(Integer param) { return param; }
        public Integer method(Integer param) { return 2*param; }
    }");
    
    # Class_Method_Moved_Up_Hierarchy
    writeFile($Path_v1."/ClassMethodMovedUpHierarchy.java",
    "package $PackageName;
    public class ClassMethodMovedUpHierarchy extends BaseClass {
        public Integer someMethod(Integer param) { return param; }
        public Integer method(Integer param) { return 2*param; }
    }");
    writeFile($Path_v2."/ClassMethodMovedUpHierarchy.java",
    "package $PackageName;
    public class ClassMethodMovedUpHierarchy extends BaseClass {
        public Integer someMethod(Integer param) { return param; }
    }");
    
    # Class_Method_Moved_Up_Hierarchy (Interface Method) - should not be reported
    writeFile($Path_v1."/InterfaceMethodMovedUpHierarchy.java",
    "package $PackageName;
    public interface InterfaceMethodMovedUpHierarchy extends BaseInterface {
        public Integer method(Integer param);
        public Integer method2(Integer param);
    }");
    writeFile($Path_v2."/InterfaceMethodMovedUpHierarchy.java",
    "package $PackageName;
    public interface InterfaceMethodMovedUpHierarchy extends BaseInterface {
        public Integer method2(Integer param);
    }");
    
    # Class_Method_Moved_Up_Hierarchy (Abstract Method) - should not be reported
    writeFile($Path_v1."/AbstractMethodMovedUpHierarchy.java",
    "package $PackageName;
    public abstract class AbstractMethodMovedUpHierarchy implements BaseInterface {
        public abstract Integer method(Integer param);
        public abstract Integer method2(Integer param);
    }");
    writeFile($Path_v2."/AbstractMethodMovedUpHierarchy.java",
    "package $PackageName;
    public abstract class AbstractMethodMovedUpHierarchy implements BaseInterface {
        public abstract Integer method2(Integer param);
    }");
    
    # Use
    writeFile($Path_v1."/Use.java",
    "package $PackageName;
    public class Use {
        public FieldBecameFinal field;
        public void someMethod(FieldBecameFinal[] param) { };
        public void someMethod(Use param) { };
        public Integer someMethod(AbstractClassAddedSuperAbstractClass param) {
            return 0;
        }
        public Integer someMethod(AbstractClassAddedAbstractMethod param) {
            return 0;
        }
        public Integer someMethod(InterfaceAddedAbstractMethod param) {
            return 0;
        }
        public Integer someMethod(InterfaceAddedSuperInterface param) {
            return 0;
        }
        public Integer someMethod(AbstractClassAddedSuperInterface param) {
            return 0;
        }
    }");
    writeFile($Path_v2."/Use.java",
    "package $PackageName;
    public class Use {
        public FieldBecameFinal field;
        public void someMethod(FieldBecameFinal[] param) { };
        public void someMethod(Use param) { };
        public Integer someMethod(AbstractClassAddedSuperAbstractClass param) {
            return param.abstractMethod(100)+param.field;
        }
        public Integer someMethod(AbstractClassAddedAbstractMethod param) {
            return param.addedMethod(100);
        }
        public Integer someMethod(InterfaceAddedAbstractMethod param) {
            return param.addedMethod(100);
        }
        public Integer someMethod(InterfaceAddedSuperInterface param) {
            return param.method2(100);
        }
        public Integer someMethod(AbstractClassAddedSuperInterface param) {
            return param.method2(100);
        }
    }");
    
    # Added_Package
    writeFile($Path_v2."/AddedPackage/AddedPackageClass.java",
    "package $PackageName.AddedPackage;
    public class AddedPackageClass {
        public Integer field;
        public void someMethod(Integer param) { };
    }");
    
    # Removed_Package
    writeFile($Path_v1."/RemovedPackage/RemovedPackageClass.java",
    "package $PackageName.RemovedPackage;
    public class RemovedPackageClass {
        public Integer field;
        public void someMethod(Integer param) { };
    }");
    my $BuildRoot1 = get_dirname($Path_v1);
    my $BuildRoot2 = get_dirname($Path_v2);
    if(compileJavaLib($LibName, $BuildRoot1, $BuildRoot2))
    {
        runTests($TestsPath, $PackageName, $BuildRoot1, $BuildRoot2);
        runChecker($LibName, $BuildRoot1, $BuildRoot2);
    }
}

sub readArchive($$)
{
    my ($LibVersion, $Path) = @_;
    return if(not $Path or not -e $Path);
    my $ArchiveName = get_filename($Path);
    $LibArchives{$LibVersion}{$ArchiveName} = 1;
    $Path = get_abs_path($Path);
    my $JarCmd = get_CmdPath("jar");
    if(not $JarCmd) {
        exitStatus("Not_Found", "can't find \"jar\" command");
    }
    my $ExtractPath = "$TMP_DIR/".($ExtractCounter++);
    rmtree($ExtractPath);
    mkpath($ExtractPath);
    system("cd \"$ExtractPath\" && $JarCmd -xf \"$Path\"");
    my @Classes = ();
    foreach my $ClassPath (cmd_find($ExtractPath,"","*\.class",""))
    {
        $ClassPath=~s/\.class\Z//g;
        my $ClassName = get_filename($ClassPath);
        next if($ClassName=~/\$\d/);
        my $RelPath = cut_path_prefix(get_dirname($ClassPath), $ExtractPath);
        $ClassPath = cut_path_prefix($ClassPath, $TMP_DIR);
        if($RelPath=~/\./)
        { # jaxb-osgi.jar/1.0/org/apache
            next;
        }
        my $Package = get_PFormat($RelPath);
        if(skip_package($Package, $LibVersion))
        {# internal packages
            next;
        }
        $ClassName=~s/\$/./g;# real name GlyphView$GlyphPainter => GlyphView.GlyphPainter
        $LibClasses{$LibVersion}{$ClassName} = $Package;
        # Javap decompiler accepts relative paths only
        push(@Classes, $ClassPath);
    }
    if($#Classes!=-1)
    {
        foreach my $PartRef (divideArray(\@Classes, $MAX_ARGS)) {
            readClasses($PartRef, $LibVersion, get_filename($Path));
        }
    }
    foreach my $SubArchive (cmd_find($ExtractPath,"","*\.jar",""))
    { # recursive step
        readArchive($LibVersion, $SubArchive);
    }
}

sub native_path($)
{
    my $Path = $_[0];
    if($OSgroup eq "windows") {
        $Path=~s/[\/\\]+/\\/g;
    }
    return $Path;
}

sub divideArray($$)
{
    my ($ArrayRef, $Size) = @_;
    return () if(not $ArrayRef);
    my @Array = @{$ArrayRef};
    return () if($#Array==-1);
    if($#Array>$Size) {
        my @Part = splice(@Array, 0, $Size);
        return (\@Part, divideArray(\@Array, $Size));
    }
    else {
        return ($ArrayRef);
    }
}

sub readUsage_Client($)
{
    my $Path = $_[0];
    return if(not $Path or not -e $Path);
    my $JarCmd = get_CmdPath("jar");
    if(not $JarCmd) {
        exitStatus("Not_Found", "can't find \"jar\" command");
    }
    $Path = get_abs_path($Path);
    my $ExtractPath = "$TMP_DIR/extracted";
    rmtree($ExtractPath);
    mkpath($ExtractPath);
    system("cd $ExtractPath && $JarCmd -xf $Path");
    my @Classes = ();
    foreach my $ClassPath (cmd_find($ExtractPath,"","*\.class","")) {
        next if(get_filename($ClassPath)=~/\$/);
        $ClassPath=~s/\.class\Z//g;
        $ClassPath = cut_path_prefix($ClassPath, $ORIG_DIR);
        push(@Classes, $ClassPath);
    }
    readUsage_Classes(\@Classes);
}

sub readUsage_Classes($)
{
    my $Paths = $_[0];
    return () if(not $Paths);
    my $JavapCmd = get_CmdPath("javap");
    if(not $JavapCmd) {
        exitStatus("Not_Found", "can't find \"javap\" command");
    }
    my $Input = join(" ", @{$Paths});
    open(CONTENT, "$JavapCmd -c -private $Input |");
    while(<CONTENT>)
    {
        if(/\/\/(Method|InterfaceMethod)\s+(.+)\Z/) {
            $UsedMethods_Client{$2} = 1;
        }
        elsif(/\/\/Field\s+(.+)\Z/) {
            my $FieldName = $1;
            if(/\s+(putfield|getfield|getstatic|putstatic)\s+/) {
                $UsedFields_Client{$FieldName} = $1;
            }
        }
    }
    close(CONTENT);
}

sub registerType($$)
{
    my ($TName, $LibVersion) = @_;
    return 0 if(not $TName);
    $TName=~s/#/./g;
    if($TName_Tid{$LibVersion}{$TName}) {
        return $TName_Tid{$LibVersion}{$TName};
    }
    if(not $TName_Tid{$LibVersion}{$TName}) {
        $TName_Tid{$LibVersion}{$TName} = ++$TypeID;
    }
    my $Tid = $TName_Tid{$LibVersion}{$TName};
    $TypeInfo{$LibVersion}{$Tid}{"Name"} = $TName;
    if($TName=~/(.+)\[\]\Z/) {
        if(my $BaseTypeId = registerType($1, $LibVersion)) {
            $TypeInfo{$LibVersion}{$Tid}{"BaseType"} = $BaseTypeId;
            $TypeInfo{$LibVersion}{$Tid}{"Type"} = "array";
        }
    }
    return $Tid;
}

sub readClasses($$$)
{
    my ($Paths, $LibVersion, $ArchiveName) = @_;
    return if(not $Paths or not $LibVersion or not $ArchiveName);
    my $JavapCmd = get_CmdPath("javap");
    if(not $JavapCmd) {
        exitStatus("Not_Found", "can't find \"javap\" command");
    }
    my $Input = join(" ", @{$Paths});
    $Input=~s/\$/\\\$/g;
    my $Output = $TMP_DIR."/class-dump.txt";
    rmtree($Output);
    my $Cmd = "$JavapCmd -s -private";
    if(not $Quick) {
        $Cmd .= " -c -verbose";
    }
    system("cd $TMP_DIR && $Cmd $Input > $Output");
    if(not -e $Output) {
        exitStatus("Error", "internal error in parser, try to reduce MAX_ARGS");
    }
    if($Debug) {
        appendFile($DEBUG_PATH{$LibVersion}."/class-dump.txt", readFile($Output));
    }
    # ! private info should be processed
    open(CONTENT, "$TMP_DIR/class-dump.txt");
    my @Content = <CONTENT>;
    close(CONTENT);
    my (%TypeAttr, $CurrentMethod, $CurrentPackage, $CurrentClass) = ();
    my ($InParamTable, $InExceptionTable, $InCode) = (0, 0);
    my ($ParamPos, $FieldPos, $LineNum) = (0, 0, 0);
    while($LineNum<=$#Content)
    {
        my $LINE = $Content[$LineNum++];
        next if($LINE=~/\A\s*(?:const|#\d|AnnotationDefault|Compiled|Source|Constant|RuntimeVisibleAnnotations)/);
        next if($LINE=~/\sof\s|\sline \d+:|\[\s*class|= \[| \$|\$\d| class\$/);
        $LINE=~s/\s*,\s*/,/g;
        $LINE=~s/\$/#/g;
        if($LINE=~/LocalVariableTable/) {
            $InParamTable += 1;
        }
        elsif($LINE=~/Exception\s+table/) {
            $InExceptionTable = 1;
        }
        elsif($LINE=~/\A\s*Code:/) {
            $InCode += 1;
        }
        elsif($LINE=~/\A\s*\d+:\s*(.*)\Z/)
        { # read Code
            if($InCode==1)
            {
                if($CheckImpl) {
                    $MethodBody{$LibVersion}{$CurrentMethod} .= "$1\n";
                }
                if($LINE=~/\/\/(Method|InterfaceMethod)\s+(.+)\Z/)
                {
                    my $InvokedName = $2;
                    if($LibVersion==2)
                    {
                        if(defined $MethodInfo{1}{$CurrentMethod}) {
                            $MethodInvoked{2}{$InvokedName}{$CurrentMethod} = 1;
                        }
                        if($LINE!~/ invokestatic / and $InvokedName!~/<init>/)
                        {
                            $InvokedName=~s/\A\"\[L(.+);"/$1/g;
                            $InvokedName=~s/#/./g;
                            # 3:   invokevirtual   #2; //Method "[Lcom/sleepycat/je/Database#DbState;".clone:()Ljava/lang/Object;
                            if($InvokedName=~/\A(.+?)\./)
                            {
                                my $NClassName = $1;
                                if($NClassName!~/\"/)
                                {
                                    $NClassName=~s!/!.!g;
                                    $ClassMethod_AddedInvoked{$NClassName}{$InvokedName} = $CurrentMethod;
                                }
                            }
                        }
                    }
                    else {
                        $MethodInvoked{1}{$InvokedName}{$CurrentMethod} = 1;
                    }
                }
                elsif($LibVersion==2 and defined $MethodInfo{1}{$CurrentMethod}
                and $LINE=~/\/\/Field\s+(.+)\Z/)
                {
                    my $UsedFieldName = $1;
                    $FieldUsed{$UsedFieldName}{$CurrentMethod} = 1;
                }
            }
        }
        elsif($CurrentMethod and $InParamTable==1 and $LINE=~/\A\s+0\s+\d+\s+\d+\s+(\w+)/)
        { # read parameter names from LocalVariableTable
            my $PName = $1;
            if($PName ne "this" and $PName=~/[a-z]/i)
            {
                if($CurrentMethod)
                {
                    if(defined $MethodInfo{$LibVersion}{$CurrentMethod}
                    and defined $MethodInfo{$LibVersion}{$CurrentMethod}{"Param"}{$ParamPos}
                    and defined $MethodInfo{$LibVersion}{$CurrentMethod}{"Param"}{$ParamPos}{"Type"})
                    {
                        $MethodInfo{$LibVersion}{$CurrentMethod}{"Param"}{$ParamPos}{"Name"} = $PName;
                        $ParamPos++;
                    }
                }
            }
        }
        elsif($CurrentClass and $LINE=~/(\A|\s+)([^\s]+)\s+([^\s]+)\s*\((.*)\)\s*(throws\s*([^\s]+)|)\s*;\Z/)
        { # attributes of methods and constructors
            my (%MethodAttr, $ParamsLine, $Exceptions) = ();
            $InParamTable = 0; # read the first local variable table
            $InCode = 0; # read the first code
            ($MethodAttr{"Return"}, $MethodAttr{"ShortName"}, $ParamsLine, $Exceptions) = ($2, $3, $4, $6);
            $MethodAttr{"ShortName"}=~s/#/./g;
            if($Exceptions)
            {
                foreach my $E (split(/,/, $Exceptions)) {
                    $MethodAttr{"Exceptions"}{registerType($E, $LibVersion)} = 1;
                }
            }
            if($LINE=~/\A(public|protected|private)\s+/) {
                $MethodAttr{"Access"} = $1;
            }
            else {
                $MethodAttr{"Access"} = "package-private";
            }
            $MethodAttr{"Class"} = registerType($TypeAttr{"Name"}, $LibVersion);
            if($MethodAttr{"ShortName"}=~/\A(|(.+)\.)\Q$CurrentClass\E\Z/)
            {
                if($2)
                {
                    $MethodAttr{"Package"} = $2;
                    $CurrentPackage = $MethodAttr{"Package"};
                    $MethodAttr{"ShortName"} = $CurrentClass;
                }
                $MethodAttr{"Constructor"} = 1;
                delete($MethodAttr{"Return"});
            }
            else
            {
                my $ReturnName = $MethodAttr{"Return"};
                $MethodAttr{"Return"} = registerType($ReturnName, $LibVersion);
            }
            
            $ParamPos = 0;
            foreach my $ParamTName (split(/\s*,\s*/, $ParamsLine))
            {
                %{$MethodAttr{"Param"}{$ParamPos}} = ("Type"=>registerType($ParamTName, $LibVersion), "Name"=>"p".($ParamPos+1));
                $ParamPos++;
            }
            $ParamPos = 0;
            if(not $MethodAttr{"Constructor"})
            { # methods
                if($CurrentPackage) {
                    $MethodAttr{"Package"} = $CurrentPackage;
                }
                if($LINE=~/(\A|\s+)abstract\s+/) {
                    $MethodAttr{"Abstract"} = 1;
                }
                if($LINE=~/(\A|\s+)final\s+/) {
                    $MethodAttr{"Final"} = 1;
                }
                if($LINE=~/(\A|\s+)static\s+/) {
                    $MethodAttr{"Static"} = 1;
                }
                if($LINE=~/(\A|\s+)native\s+/) {
                    $MethodAttr{"Native"} = 1;
                }
                if($LINE=~/(\A|\s+)synchronized\s+/) {
                    $MethodAttr{"Synchronized"} = 1;
                }
            }
            # read the Signature
            if($Content[$LineNum++]=~/Signature:\s*(.+)\Z/i)
            { # create run-time unique name ( java/io/PrintStream.println (Ljava/lang/String;)V )
                if($MethodAttr{"Constructor"}) {
                    $CurrentMethod = $CurrentClass.".\"<init>\":".$1;
                }
                else {
                    $CurrentMethod = $CurrentClass.".".$MethodAttr{"ShortName"}.":".$1;
                }
                if(my $PackageName = get_SFormat($CurrentPackage)) {
                    $CurrentMethod = $PackageName."/".$CurrentMethod;
                }
            }
            else {
                exitStatus("Error", "internal error - can't read method signature");
            }
            $MethodAttr{"Archive"} = $ArchiveName;
            if($CurrentMethod)
            {
                %{$MethodInfo{$LibVersion}{$CurrentMethod}} = %MethodAttr;
                if($MethodAttr{"Access"}=~/public|protected/)
                {
                    $Class_Methods{$LibVersion}{$TypeAttr{"Name"}}{$CurrentMethod} = 1;
                    if($MethodAttr{"Abstract"}) {
                        $Class_AbstractMethods{$LibVersion}{$TypeAttr{"Name"}}{$CurrentMethod} = 1;
                    }
                }
            }
        }
        elsif($CurrentClass and $LINE=~/(\A|\s+)([^\s]+)\s+(\w+);\Z/)
        { # fields
            my ($TName, $FName) = ($2, $3);
            $TypeAttr{"Fields"}{$FName}{"Type"} = registerType($TName, $LibVersion);
            if($LINE=~/(\A|\s+)final\s+/) {
                $TypeAttr{"Fields"}{$FName}{"Final"} = 1;
            }
            if($LINE=~/(\A|\s+)static\s+/) {
                $TypeAttr{"Fields"}{$FName}{"Static"} = 1;
            }
            if($LINE=~/(\A|\s+)transient\s+/) {
                $TypeAttr{"Fields"}{$FName}{"Transient"} = 1;
            }
            if($LINE=~/(\A|\s+)volatile\s+/) {
                $TypeAttr{"Fields"}{$FName}{"Volatile"} = 1;
            }
            if($LINE=~/\A(public|protected|private)\s+/) {
                $TypeAttr{"Fields"}{$FName}{"Access"} = $1;
            }
            else {
                $TypeAttr{"Fields"}{$FName}{"Access"} = "package-private";
            }
            if($TypeAttr{"Fields"}{$FName}{"Access"}!~/private/) {
                $Class_Fields{$LibVersion}{$TypeAttr{"Name"}}{$FName}=$TypeAttr{"Fields"}{$FName}{"Type"};
            }
            $TypeAttr{"Fields"}{$FName}{"Pos"} = $FieldPos++;
            # read the Signature
            if($Content[$LineNum++]=~/Signature:\s*(.+)\Z/i)
            {
                my $FSignature = $1;
                if(my $PackageName = get_SFormat($CurrentPackage)) {
                    $TypeAttr{"Fields"}{$FName}{"Mangled"} = $PackageName."/".$CurrentClass.".".$FName.":".$FSignature;
                }
            }
            # read the Value
            if($Content[$LineNum]=~/Constant\s+value:\s*([^\s]+)\s(.*)\Z/i)
            {
                $LineNum+=1;
                my ($TName, $Value) = ($1, $2);
                if($Value) {
                    if($Value=~s/Deprecated:\s*true\Z//g) {
                        # deprecated values: ?
                    }
                    $TypeAttr{"Fields"}{$FName}{"Value"} = $Value;
                }
                elsif($TName eq "String") {
                    $TypeAttr{"Fields"}{$FName}{"Value"} = "\@EMPTY_STRING\@";
                }
            }
        }
        elsif($LINE=~/(\A|\s+)(class|interface)\s+([^\s\{]+)(\s+|\{|\Z)/)
        { # properties of classes and interfaces
            %TypeAttr = ("Type"=>$2, "Name"=>$3); # reset previous class
            $FieldPos = 0; # reset field position
            $CurrentMethod = ""; # reset current method
            $TypeAttr{"Archive"} = $ArchiveName;
            if($TypeAttr{"Name"}=~/\A(.+)\.([^.]+)\Z/)
            {
                $CurrentClass = $2;
                $TypeAttr{"Package"} = $1;
                $CurrentPackage = $TypeAttr{"Package"};
            }
            else
            {
                $CurrentClass = $TypeAttr{"Name"};
                $CurrentPackage = "";
            }
            if($CurrentClass=~s/#/./g)
            { # javax.swing.text.GlyphView.GlyphPainter <=> GlyphView$GlyphPainter
                $TypeAttr{"Name"}=~s/#/./g;
            }
            if($LINE=~/\A(public|protected|private)\s+/) {
                $TypeAttr{"Access"} = $1;
            }
            else {
                $TypeAttr{"Access"} = "package-private";
            }
            if($LINE=~/\s+extends\s+([^\s\{]+)/)
            {
                if($TypeAttr{"Type"} eq "class") {
                    $TypeAttr{"SuperClass"} = registerType($1, $LibVersion);
                }
                elsif($TypeAttr{"Type"} eq "interface") {
                    foreach my $SuperInterface (split(/,/, $1)) {
                        $TypeAttr{"SuperInterface"}{registerType($SuperInterface, $LibVersion)} = 1;
                    }
                }
            }
            if($LINE=~/\s+implements\s+([^\s\{]+)/)
            {
                foreach my $SuperInterface (split(/,/, $1)) {
                    $TypeAttr{"SuperInterface"}{registerType($SuperInterface, $LibVersion)} = 1;
                }
            }
            if($LINE=~/(\A|\s+)abstract\s+/) {
                $TypeAttr{"Abstract"} = 1;
            }
            if($LINE=~/(\A|\s+)final\s+/) {
                $TypeAttr{"Final"} = 1;
            }
            if($LINE=~/(\A|\s+)static\s+/) {
                $TypeAttr{"Static"} = 1;
            }
        }
        else {
            # unparsed
        }
        %{$TypeInfo{$LibVersion}{registerType($TypeAttr{"Name"}, $LibVersion)}} = %TypeAttr;
    }
}

sub registerUsage($$)
{
    my ($TypeId, $LibVersion) = @_;
    $Class_Constructed{$LibVersion}{$TypeId} = 1;
    if(my $BaseId = $TypeInfo{$LibVersion}{$TypeId}{"BaseType"}) {
        $Class_Constructed{$LibVersion}{$BaseId} = 1;
    }
}

sub checkVoidMethod($)
{
    my $Method = $_[0];
    return "" if(not $Method);
    if($Method=~s/\)(.+)\Z/\)V/g) {
        return $Method;
    }
    else {
        return "";
    }
}

sub detectAdded()
{
    foreach my $Method (keys(%{$MethodInfo{2}}))
    {
        if(not defined $MethodInfo{1}{$Method}) {
            if($MethodInfo{2}{$Method}{"Access"}=~/private/)
            { # non-public methods
                next;
            }
            next if(not methodFilter($Method, 2));
            my $ClassId = $MethodInfo{2}{$Method}{"Class"};
            my %Class = get_Type($ClassId, 2);
            if($Class{"Access"}=~/private/)
            { # non-public classes
                next;
            }
            $CheckedMethods{$Method} = 1;
            if(not $MethodInfo{2}{$Method}{"Constructor"}
            and my $Overridden = findMethod($Method, 2, $Class{"Name"}, 2))
            {
                if(defined $MethodInfo{1}{$Overridden}
                and get_TypeType($ClassId, 2) eq "class" and $TName_Tid{1}{$Class{"Name"}})
                { # class should exist in previous version
                    %{$CompatProblems{$Overridden}{"Class_Overridden_Method"}{get_SFormat($Method)}}=(
                        "Type_Name"=>$Class{"Name"},
                        "Target"=>$MethodInfo{2}{$Method}{"Signature"},
                        "Old_Value"=>$MethodInfo{2}{$Overridden}{"Signature"},
                        "New_Value"=>$MethodInfo{2}{$Method}{"Signature"}  );
                }
            }
            if($MethodInfo{2}{$Method}{"Abstract"}) {
                $AddedMethod_Abstract{$Class{"Name"}}{$Method} = 1;
            }
            if(not $ShortMode) {
                %{$CompatProblems{$Method}{"Added_Method"}{""}}=();
            }
            if(not $MethodInfo{2}{$Method}{"Constructor"})
            {
                if(get_TypeName($MethodInfo{2}{$Method}{"Return"}, 2) ne "void"
                and my $VoidMethod = checkVoidMethod($Method))
                {
                    if(defined $MethodInfo{1}{$VoidMethod})
                    { # return value type changed from "void" to 
                        $ChangedReturnFromVoid{$VoidMethod} = 1;
                        $ChangedReturnFromVoid{$Method} = 1;
                        %{$CompatProblems{$VoidMethod}{"Changed_Method_Return_From_Void"}{""}}=(
                            "New_Value"=>get_TypeName($MethodInfo{2}{$Method}{"Return"}, 2)
                        );
                    }
                }
            }
        }
    }
}

sub detectRemoved()
{
    foreach my $Method (keys(%{$MethodInfo{1}}))
    {
        if(not defined $MethodInfo{2}{$Method}) {
            next if($MethodInfo{1}{$Method}{"Access"}=~/private/);
            next if(not methodFilter($Method, 1));
            my $ClassId = $MethodInfo{1}{$Method}{"Class"};
            my %Class = get_Type($ClassId, 1);
            if($Class{"Access"}=~/private/)
            {# non-public classes
                next;
            }
            $CheckedMethods{$Method} = 1;
            if(not $MethodInfo{1}{$Method}{"Constructor"} and $TName_Tid{2}{$Class{"Name"}}
            and my $MovedUp = findMethod($Method, 1, $Class{"Name"}, 2)) {
                if(get_TypeType($ClassId, 1) eq "class"
                and not $MethodInfo{1}{$Method}{"Abstract"} and $TName_Tid{2}{$Class{"Name"}})
                {# class should exist in newer version
                    %{$CompatProblems{$Method}{"Class_Method_Moved_Up_Hierarchy"}{get_SFormat($MovedUp)}}=(
                        "Type_Name"=>$Class{"Name"},
                        "Target"=>$MethodInfo{2}{$MovedUp}{"Signature"},
                        "Old_Value"=>$MethodInfo{1}{$Method}{"Signature"},
                        "New_Value"=>$MethodInfo{2}{$MovedUp}{"Signature"}  );
                }
            }
            else {
                if($MethodInfo{1}{$Method}{"Abstract"}) {
                    $RemovedMethod_Abstract{$Class{"Name"}}{$Method} = 1;
                }
                %{$CompatProblems{$Method}{"Removed_Method"}{""}}=();
            }
        }
    }
}

sub getArchives($)
{
    my $LibVersion = $_[0];
    my @Paths = ();
    foreach my $Path (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"Archives"}))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        foreach (getArchivePaths($Path, $LibVersion)) {
            push(@Paths, $_);
        }
    }
    return @Paths;
}

sub getArchivePaths($$)
{
    my ($Dest, $LibVersion) = @_;
    if(-f $Dest)
    {
        return ($Dest);
    }
    elsif(-d $Dest)
    {
        $Dest=~s/[\/\\]+\Z//g;
        my @AllClasses = ();
        foreach my $Path (cmd_find($Dest,"","*\.jar",""))
        {
            next if(ignore_path($Path, $Dest));
            push(@AllClasses, resolve_symlink($Path));
        }
        return @AllClasses;
    }
    return ();
}

sub isCyclical($$)
{
    return (grep {$_ eq $_[1]} @{$_[0]});
}

sub read_symlink($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    return $Cache{"read_symlink"}{$Path} if(defined $Cache{"read_symlink"}{$Path});
    if(my $ReadlinkCmd = get_CmdPath("readlink"))
    {
        my $Res = `$ReadlinkCmd -n $Path`;
        $Cache{"read_symlink"}{$Path} = $Res;
        return $Res;
    }
    elsif(my $FileCmd = get_CmdPath("file"))
    {
        my $Info = `$FileCmd $Path`;
        if($Info=~/symbolic\s+link\s+to\s+['`"]*([\w\d\.\-\/\\]+)['`"]*/i)
        {
            $Cache{"read_symlink"}{$Path} = $1;
            return $Cache{"read_symlink"}{$Path};
        }
    }
    $Cache{"read_symlink"}{$Path} = "";
    return "";
}

sub resolve_symlink($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    return $Path if(isCyclical(\@RecurSymlink, $Path));
    push(@RecurSymlink, $Path);
    if(-l $Path and my $Redirect=read_symlink($Path))
    {
        if(is_abs($Redirect))
        {
            my $Res = resolve_symlink($Redirect);
            pop(@RecurSymlink);
            return $Res;
        }
        elsif($Redirect=~/\.\.[\/\\]/)
        {
            $Redirect = joinPath(get_dirname($Path),$Redirect);
            while($Redirect=~s&(/|\\)[^\/\\]+(\/|\\)\.\.(\/|\\)&$1&){};
            my $Res = resolve_symlink($Redirect);
            pop(@RecurSymlink);
            return $Res;
        }
        elsif(-f get_dirname($Path)."/".$Redirect)
        {
            my $Res = resolve_symlink(joinPath(get_dirname($Path),$Redirect));
            pop(@RecurSymlink);
            return $Res;
        }
        return $Path;
    }
    else
    {
        pop(@RecurSymlink);
        return $Path;
    }
}

sub genDescriptorTemplate()
{
    writeFile("VERSION.xml", $Descriptor_Template."\n");
    print "descriptor template VERSION.xml has been generated into the current directory\n";
}

sub cmpVersions($$)
{# compare two version strings in dotted-numeric format
    my ($V1, $V2) = @_;
    return 0 if($V1 eq $V2);
    my @V1Parts = split(/\./, $V1);
    my @V2Parts = split(/\./, $V2);
    for (my $i = 0; $i <= $#V1Parts && $i <= $#V2Parts; $i++) {
        return -1 if(int($V1Parts[$i]) < int($V2Parts[$i]));
        return 1 if(int($V1Parts[$i]) > int($V2Parts[$i]));
    }
    return -1 if($#V1Parts < $#V2Parts);
    return 1 if($#V1Parts > $#V2Parts);
    return 0;
}

sub majorVersion($)
{
    my $Version = $_[0];
    return 0 if(not $Version);
    my @VParts = split(/\./, $Version);
    return $VParts[0];
}

sub isDump($)
{
    if(get_filename($_[0])=~/\A(.+)\.api(\Q.tar.gz\E|\Q.zip\E|)\Z/)
    { # returns a name of package
        return $1;
    }
    return 0;
}

sub read_API_Dump($$)
{
    my ($LibVersion, $Path) = @_;
    return if(not $LibVersion or not -e $Path);
    my $FileName = unpackDump($Path);
    if($FileName!~/\.api\Z/) {
        exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
    }
    my $Content = readFile($FileName);
    unlink($FileName);
    if($Content!~/};\s*\Z/) {
        exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
    }
    my $LibraryAPI = eval($Content);
    if(not $LibraryAPI) {
        exitStatus("Error", "internal error - eval() procedure seem to not working correctly, try to remove 'use strict' and try again");
    }
    my $DumpVersion = $LibraryAPI->{"API_DUMP_VERSION"};
    if(majorVersion($DumpVersion) ne $API_DUMP_MAJOR)
    { # compatible with the dumps of the same major version
        exitStatus("Dump_Version", "incompatible version $DumpVersion of specified ABI dump (allowed only $API_DUMP_MAJOR.0<=V<=$API_DUMP_MAJOR.9)");
    }
    $TypeInfo{$LibVersion} = $LibraryAPI->{"TypeInfo"};
    foreach my $TypeId (keys(%{$TypeInfo{$LibVersion}}))
    {
        my %TypeAttr = %{$TypeInfo{$LibVersion}{$TypeId}};
        $TName_Tid{$LibVersion}{$TypeAttr{"Name"}}=$TypeId;
        if(my $Archive = $TypeAttr{"Archive"}) {
            $LibArchives{$LibVersion}{$Archive}=1;
        }
        
        foreach my $FieldName (keys(%{$TypeAttr{"Fields"}}))
        {
            if($TypeAttr{"Fields"}{$FieldName}{"Access"}=~/public|protected/) {
                $Class_Fields{$LibVersion}{$TypeAttr{"Name"}}{$FieldName}=$TypeAttr{"Fields"}{$FieldName}{"Type"};
            }
        }
    }
    $MethodInfo{$LibVersion} = $LibraryAPI->{"MethodInfo"};
    foreach my $Method (keys(%{$MethodInfo{$LibVersion}}))
    {
        if(my $ClassId = $MethodInfo{$LibVersion}{$Method}{"Class"}
        and $MethodInfo{$LibVersion}{$Method}{"Access"}=~/public|protected/)
        {
            $Class_Methods{$LibVersion}{get_TypeName($ClassId, $LibVersion)}{$Method}=1;
            if($MethodInfo{$LibVersion}{$Method}{"Abstract"}) {
                $Class_AbstractMethods{$LibVersion}{get_TypeName($ClassId, $LibVersion)}{$Method}=1;
            }
            $LibClasses{$LibVersion}{get_ShortName($ClassId, $LibVersion)}=$MethodInfo{$LibVersion}{$Method}{"Package"};
        }
    }
    if(keys(%{$LibArchives{$LibVersion}})) {
        $Descriptor{$LibVersion}{"Archives"}="OK";
    }
    $Descriptor{$LibVersion}{"Version"} = $LibraryAPI->{"Version"};
    $Descriptor{$LibVersion}{"Dump"}=1;
}

sub createDescriptor($$)
{
    my ($LibVersion, $Path) = @_;
    return if(not $LibVersion or not $Path or not -e $Path);
    if(isDump($Path))
    { # API dump
        read_API_Dump($LibVersion, $Path);
    }
    else
    {
        if(-d $Path or $Path=~/\.jar\Z/)
        {
            readDescriptor($LibVersion,"
              <version>
                  ".$TargetVersion{$LibVersion}."
              </version>
              
              <archives>
                  $Path
              </archives>");
        }
        else
        { # standard XML descriptor
            readDescriptor($LibVersion, readFile($Path));
        }
    }
}

sub get_version($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    my $Version = `$Cmd --version 2>$TMP_DIR/null`;
    return $Version;
}

sub get_depth($)
{
    return $Cache{"get_depth"}{$_[0]} if(defined $Cache{"get_depth"}{$_[0]});
    return ($Cache{"get_depth"}{$_[0]} = ($_[0]=~tr![/\]|::!!));
}

sub show_time_interval($)
{
    my $Interval = $_[0];
    my $Hr = int($Interval/3600);
    my $Min = int($Interval/60)-$Hr*60;
    my $Sec = $Interval-$Hr*3600-$Min*60;
    if($Hr) {
        return "$Hr hr, $Min min, $Sec sec";
    }
    elsif($Min) {
        return "$Min min, $Sec sec";
    }
    else {
        return "$Sec sec";
    }
}

sub checkVersionNum($$)
{
    my ($LibVersion, $Path) = @_;
    if(my $VerNum = $TargetVersion{$LibVersion}) {
        return $VerNum;
    }
    my $Alt = 0;
    my $VerNum = "";
    foreach my $Part (split(/\s*,\s*/, $Path))
    {
        if(not $VerNum and -d $Part)
        {
            $Alt = 1;
            $Part=~s/\Q$TargetLibraryName\E//g;
            $VerNum = parseVersion($Part);
        }
        if(not $VerNum and $Part=~/\.jar\Z/i)
        {
            $Alt = 1;
            $VerNum = readJarVersion(get_abs_path($Part));
            if(not $VerNum) {
                $VerNum = getPkgVersion(get_filename($Part));
            }
            if(not $VerNum) {
                $VerNum = parseVersion($Part);
            }
        }
        if($VerNum)
        {
            $TargetVersion{$LibVersion} = $VerNum;
            print STDERR "WARNING: set ".($LibVersion==1?"1st":"2nd")." version number to $VerNum (use -v$LibVersion <num> option to change it)\n";
            return $TargetVersion{$LibVersion};
        }
    }
    if($Alt)
    {
        if($DumpAPI) {
            exitStatus("Error", "version number is not set (use -vnum <num> option)");
        }
        else {
            exitStatus("Error", ($LibVersion==1?"1st":"2nd")." version number is not set (use -v$LibVersion <num> option)");
        }
    }
}

sub readJarVersion($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -e $Path);
    my $JarCmd = get_CmdPath("jar");
    if(not $JarCmd) {
        exitStatus("Not_Found", "can't find \"jar\" command");
    }
    system("cd $TMP_DIR && $JarCmd -xf $Path META-INF 2>null");
    if(my $Content = readFile("$TMP_DIR/META-INF/MANIFEST.MF"))
    {
        if($Content=~/(\A|\s)Implementation\-Version:\s*(.+)(\s|\Z)/i) {
            return $2;
        }
    }
    return "";
}

sub parseVersion($)
{
    my $Str = $_[0];
    return "" if(not $Str);
    if($Str=~/(\/|\\|\w|\A)[\-\_]*(\d+[\d\.\-]+\d+|\d+)/) {
        return $2;
    }
    return "";
}

sub getPkgVersion($)
{
    my $Name = $_[0];
    $Name=~s/\.\w+\Z//;
    if($Name=~/\A(.+[a-z])[\-\_](\d.+?)\Z/i)
    { # libsample-N
        return ($1, $2);
    }
    elsif($Name=~/\A(.+)[\-\_](.+?)\Z/i)
    { # libsample-N
        return ($1, $2);
    }
    elsif($Name=~/\A(.+?)(\d[\d\.]*)\Z/i)
    { # libsampleN
        return ($1, $2);
    }
    elsif($Name=~/\A([a-z_\-]+)(\d.+?)\Z/i)
    { # libsampleNb
        return ($1, $2);
    }
    return ();
}

sub get_OSgroup()
{
    if($Config{"osname"}=~/macos|darwin|rhapsody/i) {
        return "macos";
    }
    elsif($Config{"osname"}=~/freebsd|openbsd|netbsd/i) {
        return "bsd";
    }
    elsif($Config{"osname"}=~/haiku|beos/i) {
        return "beos";
    }
    elsif($Config{"osname"}=~/symbian|epoc/i) {
        return "symbian";
    }
    elsif($Config{"osname"}=~/win/i) {
        return "windows";
    }
    else {
        return $Config{"osname"};
    }
}

sub dump_sorting($)
{
    my $Hash = $_[0];
    return [] if(not $Hash);
    my @Keys = keys(%{$Hash});
    return [] if($#Keys<0);
    if($Keys[0]=~/\A\d+\Z/)
    { # numbers
        return [sort {int($a)<=>int($b)} @Keys];
    }
    else
    { # strings
        return [sort {$a cmp $b} @Keys];
    }
}

sub detect_bin_default_paths()
{
    my $EnvPaths = $ENV{"PATH"};
    if($OSgroup eq "beos") {
        $EnvPaths.=":".$ENV{"BETOOLS"};
    }
    elsif($OSgroup eq "windows"
    and my $JHome = $ENV{"JAVA_HOME"}) {
        $EnvPaths.=";$JHome\\bin";
    }
    my $Sep = ($OSgroup eq "windows")?";":":|;";
    foreach my $Path (sort {length($a)<=>length($b)} split(/$Sep/, $EnvPaths))
    {
        $Path=~s/[\/\\]+\Z//g;
        next if(not $Path);
        $DefaultBinPaths{$Path} = 1;
    }
}

sub detect_default_paths()
{
    foreach my $Type (keys(%{$OS_AddPath{$OSgroup}}))
    {# additional search paths
        foreach my $Path (keys(%{$OS_AddPath{$OSgroup}{$Type}}))
        {
            next if(not -d $Path);
            $SystemPaths{$Type}{$Path} = $OS_AddPath{$OSgroup}{$Type}{$Path};
        }
    }
    if($OSgroup ne "windows")
    {
        foreach my $Type ("include", "lib", "bin")
        {# autodetecting system "devel" directories
            foreach my $Path (cmd_find("/","d","*$Type*",1)) {
                $SystemPaths{$Type}{$Path} = 1;
            }
            if(-d "/usr") {
                foreach my $Path (cmd_find("/usr","d","*$Type*",1)) {
                    $SystemPaths{$Type}{$Path} = 1;
                }
            }
        }
    }
    detect_bin_default_paths();
    foreach my $Path (keys(%DefaultBinPaths)) {
        $SystemPaths{"bin"}{$Path} = $DefaultBinPaths{$Path};
    }
}

sub exitStatus($$)
{
    my ($Code, $Msg) = @_;
    print STDERR "ERROR: ". $Msg."\n";
    exit($ERROR_CODE{$Code});
}

sub printMsg($$)
{
    my ($Type, $Msg) = @_;
    if($Type!~/\AINFO/) {
        $Msg = $Type.": ".$Msg;
    }
    if($Type!~/_C\Z/) {
        $Msg .= "\n";
    }
    if($Type eq "ERROR") {
        print STDERR $Msg;
    }
    else {
        print $Msg;
    }
}

sub printStatMsg($)
{
    my $Level = $_[0];
    printMsg("INFO", "total \"$Level\" compatibility problems: ".$RESULT{$Level}{"Problems"}.", warnings: ".$RESULT{$Level}{"Warnings"});
}

sub printReport()
{
    printMsg("INFO", "creating compatibility report ...");
    createReport();
    if($JoinReport or $DoubleReport)
    {
        if($RESULT{"Binary"}{"Problems"}
        or $RESULT{"Source"}{"Problems"}) {
            printMsg("INFO", "result: INCOMPATIBLE (Binary: ".$RESULT{"Binary"}{"Affected"}."\%, Source: ".$RESULT{"Source"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "result: COMPATIBLE");
        }
        printStatMsg("Binary");
        printStatMsg("Source");
    }
    elsif($BinaryOnly)
    {
        if($RESULT{"Binary"}{"Problems"}) {
            printMsg("INFO", "result: INCOMPATIBLE (".$RESULT{"Binary"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "result: COMPATIBLE");
        }
        printStatMsg("Binary");
    }
    elsif($SourceOnly)
    {
        if($RESULT{"Source"}{"Problems"}) {
            printMsg("INFO", "result: INCOMPATIBLE (".$RESULT{"Source"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "result: COMPATIBLE");
        }
        printStatMsg("Source");
    }
    if($JoinReport)
    {
        printMsg("INFO", "see detailed report:\n  ".getReportPath("Join"));
    }
    elsif($DoubleReport)
    { # default
        printMsg("INFO", "see detailed reports:\n  ".getReportPath("Binary")."\n  ".getReportPath("Source"));
    }
    elsif($BinaryOnly)
    { # --binary
        printMsg("INFO", "see detailed report:\n  ".getReportPath("Binary"));
    }
    elsif($SourceOnly)
    { # --source
        printMsg("INFO", "see detailed report:\n  ".getReportPath("Source"));
    }
}

sub getReportPath($)
{
    my $Level = $_[0];
    my $Dir = "compat_reports/$TargetLibraryName/".$Descriptor{1}{"Version"}."_to_".$Descriptor{2}{"Version"};
    if($Level eq "Binary")
    {
        if($BinaryReportPath)
        { # --bin-report-path
            return $BinaryReportPath;
        }
        elsif($OutputReportPath)
        { # --report-path
            return $OutputReportPath;
        }
        else
        { # default
            return $Dir."/bin_compat_report.html";
        }
    }
    elsif($Level eq "Source")
    {
        if($SourceReportPath)
        { # --src-report-path
            return $SourceReportPath;
        }
        elsif($OutputReportPath)
        { # --report-path
            return $OutputReportPath;
        }
        else
        { # default
            return $Dir."/src_compat_report.html";
        }
    }
    else
    {
        if($OutputReportPath)
        { # --report-path
            return $OutputReportPath;
        }
        else
        { # default
            return $Dir."/compat_report.html";
        }
    }
}

sub initLogging($)
{
    my $LibVersion = $_[0];
    if($Debug)
    { # debug directory
        $DEBUG_PATH{$LibVersion} = "debug/$TargetLibraryName/".$Descriptor{$LibVersion}{"Version"};
        rmtree($DEBUG_PATH{$LibVersion});
    }
}

sub createArchive($$)
{
    my ($Path, $To) = @_;
    if(not $Path or not -e $Path
    or not -d $To) {
        return "";
    }
    my ($From, $Name) = separate_path($Path);
    if($OSgroup eq "windows")
    { # *.zip
        my $ZipCmd = get_CmdPath("zip");
        if(not $ZipCmd) {
            exitStatus("Not_Found", "can't find \"zip\"");
        }
        my $Pkg = $To."/".$Name.".zip";
        unlink($Pkg);
        chdir($To);
        system("$ZipCmd -j \"$Name.zip\" \"$Path\" >$TMP_DIR/null");
        if($?)
        { # cannot allocate memory (or other problems with "zip")
            unlink($Path);
            exitStatus("Error", "can't pack the ABI dump: ".$!);
        }
        chdir($ORIG_DIR);
        unlink($Path);
        return $Pkg;
    }
    else
    { # *.tar.gz
        my $TarCmd = get_CmdPath("tar");
        if(not $TarCmd) {
            exitStatus("Not_Found", "can't find \"tar\"");
        }
        my $GzipCmd = get_CmdPath("gzip");
        if(not $GzipCmd) {
            exitStatus("Not_Found", "can't find \"gzip\"");
        }
        my $Pkg = abs_path($To)."/".$Name.".tar.gz";
        unlink($Pkg);
        chdir($From);
        system($TarCmd, "-czf", $Pkg, $Name);
        if($?)
        { # cannot allocate memory (or other problems with "tar")
            unlink($Path);
            exitStatus("Error", "can't pack the ABI dump: ".$!);
        }
        chdir($ORIG_DIR);
        unlink($Path);
        return $To."/".$Name.".tar.gz";
    }
}

sub scenario()
{
    if($BinaryOnly and $SourceOnly)
    { # both --binary and --source
      # is the default mode
        $DoubleReport = 1;
        $JoinReport = 0;
        $BinaryOnly = 0;
        $SourceOnly = 0;
        if($OutputReportPath)
        { # --report-path
            $DoubleReport = 0;
            $JoinReport = 1;
        }
    }
    elsif($BinaryOnly or $SourceOnly)
    { # --binary or --source
        $DoubleReport = 0;
        $JoinReport = 0;
    }
    if(defined $Help) {
        HELP_MESSAGE();
        exit(0);
    }
    if(defined $ShowVersion) {
        print "Java API Compliance Checker (Java ACC) $TOOL_VERSION\nCopyright (C) 2012 ROSA Laboratory\nLicense: LGPL or GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.\n";
        exit(0);
    }
    if(defined $DumpVersion) {
        print $TOOL_VERSION."\n";
        exit(0);
    }
    $Data::Dumper::Sortkeys = 1;
    
    # FIXME: can't pass \&dump_sorting - cause a segfault sometimes
    # $Data::Dumper::Useperl = 1;
    # $Data::Dumper::Sortkeys = \&dump_sorting;
    
    detect_default_paths();
    if(defined $TestSystem) {
        testSystem();
        exit(0);
    }
    if($GenerateDescriptor) {
        genDescriptorTemplate();
        exit(0);
    }
    if(not $TargetLibraryName)
    {
        if($DumpAPI)
        {
            if($DumpAPI=~/\.jar\Z/)
            { # short usage: -old OLD.jar -new NEW.jar
                my ($Name, $Version) = getPkgVersion(get_filename($DumpAPI));
                if($Name and $Version ne "")
                {
                    $TargetLibraryName = $Name;
                    if(not $TargetVersion{1}) {
                        $TargetVersion{1} = $Version;
                    }
                }
            }
        }
        else
        {
            if($Descriptor{1}{"Path"}=~/\.jar\Z/ and $Descriptor{1}{"Path"}=~/\.jar\Z/)
            { # short usage: -old OLD.jar -new NEW.jar
                my ($Name1, $Version1) = getPkgVersion(get_filename($Descriptor{1}{"Path"}));
                my ($Name2, $Version2) = getPkgVersion(get_filename($Descriptor{2}{"Path"}));
                if($Name1 and $Version1 ne "" and $Version2 ne "")
                {
                    $TargetLibraryName = $Name1;
                    if(not $TargetVersion{1}) {
                        $TargetVersion{1} = $Version1;
                    }
                    if(not $TargetVersion{2}) {
                        $TargetVersion{2} = $Version2;
                    }
                }
            }
        }
        if(not $TargetLibraryName) {
            exitStatus("Error", "library name is not selected (option -l <name>)");
        }
    }
    else
    { # validate library name
        if($TargetLibraryName=~/[\*\/\\]/) {
            exitStatus("Error", "\"\\\", \"\/\" and \"*\" symbols are not allowed in the library name");
        }
    }
    if(not $TargetLibraryFullName) {
        $TargetLibraryFullName = $TargetLibraryName;
    }
    if($ClassListPath)
    {
        if(not -f $ClassListPath) {
            exitStatus("Access_Error", "can't access file \'$ClassListPath\'");
        }
        foreach my $Method (split(/\n/, readFile($ClassListPath))) {
            $ClassList_User{$Method} = 1;
        }
    }
    if($ClientPath)
    {
        if(-f $ClientPath) {
            readUsage_Client($ClientPath)
        }
        else {
            exitStatus("Access_Error", "can't access file \'$ClientPath\'");
        }
    }
    if($DumpAPI)
    {
        foreach my $Part (split(/\s*,\s*/, $DumpAPI))
        {
            if(not -e $Part) {
                exitStatus("Access_Error", "can't access \'$Part\'");
            }
        }
        checkVersionNum(1, $DumpAPI);
        my $TarCmd = get_CmdPath("tar");
        if(not $TarCmd) {
            exitStatus("Not_Found", "can't find \"tar\"");
        }
        my $GzipCmd = get_CmdPath("gzip");
        if(not $GzipCmd) {
            exitStatus("Not_Found", "can't find \"gzip\"");
        }
        foreach my $Part (split(/\s*,\s*/, $DumpAPI)) {
            createDescriptor(1, $Part);
        }
        if(not $Descriptor{1}{"Archives"}) {
            exitStatus("Error", "descriptor does not contain Java ARchives");
        }
        initLogging(1);
        readArchives(1);
        my %LibraryAPI = ();
        print "creating library API dump ...\n";
        $LibraryAPI{"MethodInfo"} = $MethodInfo{1};
        $LibraryAPI{"TypeInfo"} = $TypeInfo{1};
        $LibraryAPI{"Version"} = $Descriptor{1}{"Version"};
        $LibraryAPI{"Library"} = $TargetLibraryName;
        $LibraryAPI{"API_DUMP_VERSION"} = $API_DUMP_VERSION;
        $LibraryAPI{"TOOL_VERSION"} = $TOOL_VERSION;
        my $DumpPath = "api_dumps/$TargetLibraryName/".$TargetLibraryName."_".$Descriptor{1}{"Version"}.".api.".$AR_EXT;
        if(not $DumpPath=~s/\Q.$AR_EXT\E\Z//g) {
            exitStatus("Error", "the dump path (-dump-path option) should be a path to a *.$AR_EXT file");
        }
        my ($DDir, $DName) = separate_path($DumpPath);
        my $DPath = $TMP_DIR."/".$DName;
        mkpath($DDir);
        writeFile($DPath, Dumper(\%LibraryAPI));
        if(not -s $DPath) {
            exitStatus("Error", "can't create ABI dump because something is going wrong with the Data::Dumper module");
        }
        my $Pkg = createArchive($DPath, $DDir);
        print "library API has been dumped to:\n  $Pkg\n";
        print "you can transfer this dump everywhere and use instead of the ".$Descriptor{1}{"Version"}." version descriptor\n";
        exit(0);
    }
    if(not $Descriptor{1}{"Path"}) {
        exitStatus("Error", "-old option is not specified");
    }
    foreach my $Part (split(/\s*,\s*/, $Descriptor{1}{"Path"}))
    {
        if(not -e $Part) {
            exitStatus("Access_Error", "can't access \'$Part\'");
        }
    }
    if(not $Descriptor{2}{"Path"}) {
        exitStatus("Error", "-new option is not specified");
    }
    foreach my $Part (split(/\s*,\s*/, $Descriptor{2}{"Path"}))
    {
        if(not -e $Part) {
            exitStatus("Access_Error", "can't access \'$Part\'");
        }
    }
    checkVersionNum(1, $Descriptor{1}{"Path"});
    checkVersionNum(2, $Descriptor{2}{"Path"});
    foreach my $Part (split(/\s*,\s*/, $Descriptor{1}{"Path"})) {
        createDescriptor(1, $Part);
    }
    foreach my $Part (split(/\s*,\s*/, $Descriptor{2}{"Path"})) {
        createDescriptor(2, $Part);
    }
    if(not $Descriptor{1}{"Archives"}) {
        exitStatus("Error", "descriptor d1 does not contain Java ARchives");
    }
    if(not $Descriptor{2}{"Archives"}) {
        exitStatus("Error", "descriptor d2 does not contain Java ARchives");
    }
    initLogging(1);
    initLogging(2);
    if($Descriptor{1}{"Archives"}
    and not $Descriptor{1}{"Dump"}) {
        readArchives(1);
    }
    if($Descriptor{2}{"Archives"}
    and not $Descriptor{2}{"Dump"}) {
        readArchives(2);
    }
    foreach my $ClassName (keys(%ClassMethod_AddedInvoked))
    {
        foreach my $MethodName (keys(%{$ClassMethod_AddedInvoked{$ClassName}}))
        {
            if(defined $MethodInfo{1}{$MethodName}
            or defined $MethodInfo{2}{$MethodName}
            or defined $MethodInvoked{1}{$MethodName}
            or findMethod($MethodName, 2, $ClassName, 1))
            { # abstract method added by the new super-class (abstract) or super-interface
                delete($ClassMethod_AddedInvoked{$ClassName}{$MethodName});
            }
        }
        if(not keys(%{$ClassMethod_AddedInvoked{$ClassName}})) {
            delete($ClassMethod_AddedInvoked{$ClassName});
        }
    }
    prepareMethods(1);
    prepareMethods(2);
    
    detectAdded();
    detectRemoved();
    
    print "comparing classes ...\n";
    mergeClasses();
    
    mergeMethods();
    if($CheckImpl) {
        mergeImplementations();
    }
    printReport();
    if($RESULT{"Source"}{"Problems"} + $RESULT{"Binary"}{"Problems"}) {
        exit($ERROR_CODE{"Incompatible"});
    }
    else {
        exit($ERROR_CODE{"Compatible"});
    }
}

scenario();
