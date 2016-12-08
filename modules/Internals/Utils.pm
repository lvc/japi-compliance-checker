###########################################################################
# A module with basic functions
#
# Copyright (C) 2016 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
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
use strict;
use Cwd qw(realpath);

my $ARG_MAX = getArgMax();

sub initAPI($)
{
    my $V = $_[0];
    foreach my $K ("MethodInfo", "TypeInfo", "TName_Tid")
    {
        if(not defined $In::API{$V}{$K}) {
            $In::API{$V}{$K} = {};
        }
    }
}

sub setTarget($)
{
    my $Target = $_[0];
    
    if($Target eq "default")
    {
        $Target = getOSgroup();
        
        $In::Opt{"OS"} = $Target;
        $In::Opt{"Ar"} = getArExt($Target);
    }
    
    $In::Opt{"Target"} = $Target;
}

sub join_P($$)
{
    my $S = "/";
    if($In::Opt{"OS"} eq "windows") {
        $S = "\\";
    }
    return join($S, @_);
}

sub getArgMax()
{
    if($In::Opt{"OS"} eq "windows") {
        return 1990;
    }
    else
    { # Linux
      # TODO: set max possible value (~131000)
        return 32767;
    }
}

sub divideArray($)
{
    my $ArrRef = $_[0];
    
    my @Array = @{$ArrRef};
    return () if($#{$ArrRef}==-1);
    
    my @Res = ();
    my $Sub = [];
    my $Len = 0;
    
    foreach my $Pos (0 .. $#{$ArrRef})
    {
        my $Arg = $ArrRef->[$Pos];
        my $Arg_L = length($Arg) + 1; # space
        if($Len < $ARG_MAX - 250)
        {
            push(@{$Sub}, $Arg);
            $Len += $Arg_L;
        }
        else
        {
            push(@Res, $Sub);
            
            $Sub = [$Arg];
            $Len = $Arg_L;
        }
    }
    
    if($#{$Sub}!=-1) {
        push(@Res, $Sub);
    }
    
    return @Res;
}

sub cmdFind($$$$)
{
    my ($Path, $Type, $Name, $MaxDepth) = @_;
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    if($In::Opt{"OS"} eq "windows")
    {
        $Path=~s/[\\]+\Z//;
        $Path = getAbsPath($Path);
        my $Cmd = "dir \"$Path\" /B /O";
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
            @Files = split(/\n/, `$Cmd 2>\"$TmpDir/null\"`);
        }
        my @AbsPaths = ();
        foreach my $File (@Files)
        {
            if(not isAbs($File)) {
                $File = join_P($Path, $File);
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
        my $FindCmd = "find";
        if(not checkCmd($FindCmd)) {
            exitStatus("Not_Found", "can't find a \"find\" command");
        }
        $Path = getAbsPath($Path);
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
        return split(/\n/, `$Cmd 2>\"$TmpDir/null\"`);
    }
}

sub getAbsPath($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them
    my $Path = $_[0];
    if(not isAbs($Path)) {
        $Path = abs_path($Path);
    }
    return pathFmt($Path, $In::Opt{"OS"});
}

sub pathFmt(@)
{
    my $Path = shift(@_);
    my $Fmt = $In::Opt{"OS"};
    if(@_) {
        $Fmt = shift(@_);
    }
    
    $Path=~s/[\/\\]+\.?\Z//g;
    if($Fmt eq "windows")
    {
        $Path=~s/\//\\/g;
        $Path = lc($Path);
    }
    else {
        $Path=~s/\\/\//g;
    }
    
    $Path=~s/[\/\\]+\Z//g;
    
    return $Path;
}

sub realpath_F($)
{
    my $Path = $_[0];
    return pathFmt(realpath($Path));
}

sub unpackDump($)
{
    my $Path = $_[0];
    
    if(isDump_U($Path)) {
        return $Path;
    }
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    $Path = getAbsPath($Path);
    $Path = pathFmt($Path);
    
    my ($Dir, $FileName) = sepPath($Path);
    my $UnpackDir = $TmpDir."/unpack";
    if(-d $UnpackDir) {
        rmtree($UnpackDir);
    }
    mkpath($UnpackDir);
    
    if($FileName=~s/\Q.zip\E\Z//g)
    { # *.zip
        my $UnzipCmd = getCmdPath("unzip");
        if(not $UnzipCmd) {
            exitStatus("Not_Found", "can't find \"unzip\" command");
        }
        chdir($UnpackDir);
        system("$UnzipCmd \"$Path\" >contents.txt");
        if($?) {
            exitStatus("Error", "can't extract \'$Path\'");
        }
        chdir($In::Opt{"OrigDir"});
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
        return join_P($UnpackDir, $Contents[0]);
    }
    elsif($FileName=~s/\Q.tar.gz\E\Z//g)
    { # *.tar.gz
        if($In::Opt{"OS"} eq "windows")
        { # -xvzf option is not implemented in tar.exe (2003)
          # use "gzip.exe -k -d -f" + "tar.exe -xvf" instead
            my $TarCmd = getCmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            my $GzipCmd = getCmdPath("gzip");
            if(not $GzipCmd) {
                exitStatus("Not_Found", "can't find \"gzip\" command");
            }
            chdir($UnpackDir);
            qx/$GzipCmd -k -d -f "$Path"/; # keep input files (-k)
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            my @Contents = qx/$TarCmd -xvf "$Dir\\$FileName.tar"/;
            if($? or not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            chdir($In::Opt{"OrigDir"});
            unlink($Dir."/".$FileName.".tar");
            chomp $Contents[0];
            return join_P($UnpackDir, $Contents[0]);
        }
        else
        { # Linux, Unix, OS X
            my $TarCmd = getCmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            chdir($UnpackDir);
            my @Contents = qx/$TarCmd -xvzf "$Path" 2>&1/;
            if($? or not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            chdir($In::Opt{"OrigDir"});
            $Contents[0]=~s/^x //; # OS X
            chomp $Contents[0];
            return join_P($UnpackDir, $Contents[0]);
        }
    }
}

sub getVersion($)
{
    my $Cmd = $_[0];
    my $TmpDir = $In::Opt{"Tmp"};
    my $Ver = `$Cmd --version 2>\"$TmpDir/null\"`;
    return $Ver;
}

return 1;
