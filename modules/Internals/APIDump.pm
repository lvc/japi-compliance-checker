###########################################################################
# A module to create API dump from disassembled code
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

my $ExtractCounter = 0;

my %MName_Mid;
my %Mid_MName;

my $T_ID = 0;
my $M_ID = 0;
my $U_ID = 0;

# Aliases
my (%MethodInfo, %TypeInfo, %TName_Tid) = ();

foreach (1, 2)
{
    $MethodInfo{$_} = $In::API{$_}{"MethodInfo"};
    $TypeInfo{$_} = $In::API{$_}{"TypeInfo"};
    $TName_Tid{$_} = $In::API{$_}{"TName_Tid"};
}

sub createAPIDump($)
{
    my $LVer = $_[0];
    
    readArchives($LVer);
    
    if(not keys(%{$MethodInfo{$LVer}})) {
        printMsg("WARNING", "empty dump");
    }
    
    $In::API{$LVer}{"LibraryVersion"} = $In::Desc{$LVer}{"Version"};
    $In::API{$LVer}{"LibraryName"} = $In::Opt{"TargetLib"};
    $In::API{$LVer}{"Language"} = "Java";
}

sub readArchives($)
{
    my $LVer = $_[0];
    my @ArchivePaths = getArchives($LVer);
    if($#ArchivePaths==-1) {
        exitStatus("Error", "Java archives are not found in ".$In::Desc{$LVer}{"Version"});
    }
    printMsg("INFO", "Reading classes ".$In::Desc{$LVer}{"Version"}." ...");
    
    $T_ID = 0;
    $M_ID = 0;
    $U_ID = 0;
    
    %MName_Mid = ();
    %Mid_MName = ();
    
    foreach my $ArchivePath (sort {length($a)<=>length($b)} @ArchivePaths) {
        readArchive($LVer, $ArchivePath);
    }
    foreach my $TName (keys(%{$TName_Tid{$LVer}}))
    {
        my $Tid = $TName_Tid{$LVer}{$TName};
        if(not $TypeInfo{$LVer}{$Tid}{"Type"})
        {
            if($TName=~/\A(void|boolean|char|byte|short|int|float|long|double)\Z/) {
                $TypeInfo{$LVer}{$Tid}{"Type"} = "primitive";
            }
            else {
                $TypeInfo{$LVer}{$Tid}{"Type"} = "class";
            }
        }
    }
}

sub getArchives($)
{
    my $LVer = $_[0];
    my @Paths = ();
    foreach my $Path (keys(%{$In::Desc{$LVer}{"Archives"}}))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        
        foreach (getArchivePaths($Path, $LVer)) {
            push(@Paths, $_);
        }
    }
    return @Paths;
}

sub readArchive($$)
{ # 1, 2 - library, 0 - client
    my ($LVer, $Path) = @_;
    
    $Path = getAbsPath($Path);
    my $JarCmd = getCmdPath("jar");
    if(not $JarCmd) {
        exitStatus("Not_Found", "can't find \"jar\" command");
    }
    my $ExtractPath = join_P($In::Opt{"Tmp"}, $ExtractCounter);
    if(-d $ExtractPath) {
        rmtree($ExtractPath);
    }
    mkpath($ExtractPath);
    chdir($ExtractPath);
    system($JarCmd." -xf \"$Path\"");
    if($?) {
        exitStatus("Error", "can't extract \'$Path\'");
    }
    chdir($In::Opt{"OrigDir"});
    my @Classes = ();
    foreach my $ClassPath (cmdFind($ExtractPath,"","*\.class",""))
    {
        if($In::Opt{"OS"} ne "windows") {
            $ClassPath=~s/\.class\Z//g;
        }
        
        my $ClassName = getFilename($ClassPath);
        if($ClassName=~/\$\d/) {
            next;
        }
        $ClassPath = cutPrefix($ClassPath, $ExtractPath); # javap decompiler accepts relative paths only
        
        my $ClassDir = getDirname($ClassPath);
        if($ClassDir=~/\./)
        { # jaxb-osgi.jar/1.0/org/apache
            next;
        }
        
        my $Package = getPFormat($ClassDir);
        if($LVer)
        {
            if(skipPackage($Package, $LVer))
            { # internal packages
                next;
            }
        }
        
        $ClassName=~s/\$/./g; # real name for GlyphView$GlyphPainter is GlyphView.GlyphPainter
        push(@Classes, $ClassPath);
    }
    
    if($#Classes!=-1)
    {
        foreach my $PartRef (divideArray(\@Classes))
        {
            if($LVer) {
                readClasses($PartRef, $LVer, getFilename($Path));
            }
            else {
                readClasses_Usage($PartRef);
            }
        }
    }
    
    $ExtractCounter+=1;
    
    if($LVer)
    {
        foreach my $SubArchive (cmdFind($ExtractPath,"","*\.jar",""))
        { # recursive step
            readArchive($LVer, $SubArchive);
        }
    }
    
    rmtree($ExtractPath);
}

sub readClasses($$$)
{
    my ($Paths, $LVer, $ArchiveName) = @_;
    
    my $JavapCmd = getCmdPath("javap");
    if(not $JavapCmd) {
        exitStatus("Not_Found", "can't find \"javap\" command");
    }
    
    my $Input = join(" ", @{$Paths});
    if($In::Opt{"OS"} ne "windows")
    { # on unix ensure that the system does not try and interpret the $, by escaping it
        $Input=~s/\$/\\\$/g;
    }
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    my $Output = $TmpDir."/class-dump.txt";
    if(-e $Output) {
        unlink($Output);
    }
    
    my $Cmd = "$JavapCmd -s -private";
    if(not $In::Opt{"Quick"}) {
        $Cmd .= " -c -verbose";
    }
    
    chdir($TmpDir."/".$ExtractCounter);
    system($Cmd." ".$Input." >\"$Output\" 2>\"$TmpDir/warn\"");
    chdir($In::Opt{"OrigDir"});
    
    if(not -e $Output) {
        exitStatus("Error", "internal error in parser, try to reduce ARG_MAX");
    }
    if($In::Opt{"Debug"}) {
        appendFile(getDebugDir($LVer)."/class-dump.txt", readFile($Output));
    }
    
    # ! private info should be processed
    open(CONTENT, "$TmpDir/class-dump.txt");
    my @Content = <CONTENT>;
    close(CONTENT);
    
    my (%TypeAttr, $CurrentMethod, $CurrentPackage, $CurrentClass) = ();
    my ($InParamTable, $InExceptionTable, $InCode) = (0, 0, 0);
    
    my $InAnnotations = undef;
    my $InAnnotations_Class = undef;
    my $InAnnotations_Method = undef;
    my %AnnotationName = ();
    my %AnnotationNum = (); # support for Java 7
    
    my ($ParamPos, $FieldPos, $LineNum) = (0, 0, 0);
    while($LineNum<=$#Content)
    {
        my $LINE = $Content[$LineNum++];
        my $LINE_N = $Content[$LineNum];
        
        if($LINE=~/\A\s*(?:const|AnnotationDefault|Compiled|Source|Constant)/) {
            next;
        }
        
        if($LINE=~/\sof\s|\sline \d+:|\[\s*class|= \[|\$[\d\$\(:\.;]| class\$|[\.\/]\$|\._\d|\$eq/)
        { # artificial methods and code
            next;
        }
        
        if($LINE=~/ (\w+\$|)\w+\$\w+[\(:]/) {
            next;
        }
        
        # $LINE=~s/ \$(\w)/ $1/g;
        # $LINE_N=~s/ \$(\w)/ $1/g;
        
        if(not $InParamTable)
        {
            if($LINE=~/ \$/) {
                next;
            }
        }
        
        $LINE=~s/\$([\> ]|\Z)/$1/g;
        $LINE_N=~s/\$([\> ]|\Z)/$1/g;
        
        if($LINE eq "\n" or $LINE eq "}\n")
        {
            $CurrentMethod = undef;
            $InCode = 0;
            $InAnnotations_Method = 0;
            $InParamTable = 0;
        }
        
        if($LINE eq "}\n") {
            $InAnnotations_Class = 1;
        }
        
        if($LINE=~/\A\s*#(\d+)/)
        { # Constant pool
            my $CNum = $1;
            if($LINE=~/\s+([^ ]+?);/)
            {
                my $AName = $1;
                $AName=~s/\AL//;
                $AName=~s/\$/./g;
                $AName=~s/\//./g;
                
                $AnnotationName{$CNum} = $AName;
                
                if(defined $AnnotationNum{$CNum})
                { # support for Java 7
                    if($InAnnotations_Class) {
                        $TypeAttr{"Annotations"}{registerType($AName, $LVer)} = 1;
                    }
                    delete($AnnotationNum{$CNum});
                }
            }
            
            next;
        }
        
        # Java 7: templates
        if(index($LINE, "<")!=-1)
        { # <T extends java.lang.Object>
          # <KEYIN extends java.lang.Object ...
            if($LINE=~/<[A-Z\d\?]+ /i)
            {
                while($LINE=~/<([A-Z\d\?]+ .*?)>( |\Z)/i)
                {
                    my $Str = $1;
                    my @Prms = ();
                    foreach my $P (sepParams($Str, 0, 0))
                    {
                        $P=~s/\A([A-Z\d\?]+) .*\Z/$1/ig;
                        push(@Prms, $P);
                    }
                    my $Str_N = join(", ", @Prms);
                    $LINE=~s/\Q$Str\E/$Str_N/g;
                }
            }
        }
        
        $LINE=~s/\s*,\s*/,/g;
        $LINE=~s/\$/#/g;
        
        if(index($LINE, "LocalVariableTable")!=-1) {
            $InParamTable += 1;
        }
        elsif($LINE=~/Exception\s+table/) {
            $InExceptionTable = 1;
        }
        elsif($LINE=~/\A\s*Code:/)
        {
            $InCode += 1;
            $InAnnotations = undef;
        }
        elsif($LINE=~/\A\s*\d+:\s*(.*)\Z/)
        { # read Code
            if($InCode==1)
            {
                if($CurrentMethod)
                {
                    if(index($LINE, "invoke")!=-1)
                    {
                        if($LINE=~/ invoke(\w+) .* \/\/\s*(Method|InterfaceMethod)\s+(.+)\Z/)
                        { # 3:   invokevirtual   #2; //Method "[Lcom/sleepycat/je/Database#DbState;".clone:()Ljava/lang/Object;
                            my ($InvokeType, $InvokedName) = ($1, $3);
                            
                            if($InvokedName!~/\A(\w+:|java\/(lang|util|io)\/)/
                            and index($InvokedName, '"<init>":')!=0)
                            {
                                $InvokedName=~s/#/\$/g;
                                
                                my $ID = undef;
                                if($In::Opt{"Reproducible"}) {
                                    $ID = getMd5($InvokedName);
                                }
                                else {
                                    $ID = ++$U_ID;
                                }
                                
                                $In::API{$LVer}{"MethodUsed"}{$ID}{"Name"} = $InvokedName;
                                $In::API{$LVer}{"MethodUsed"}{$ID}{"Used"}{$CurrentMethod} = $InvokeType;
                            }
                        }
                    }
                    # elsif($LINE=~/ (getstatic|putstatic) .* \/\/\s*Field\s+(.+)\Z/)
                    # {
                    #     my $UsedFieldName = $2;
                    #     $In::API{$LVer}{"FieldUsed"}{$UsedFieldName}{$CurrentMethod} = 1;
                    # }
                }
            }
            elsif(defined $InAnnotations)
            {
                if($LINE=~/\A\s*\d+\:\s*#(\d+)/)
                {
                    if(my $AName = $AnnotationName{$1})
                    {
                        if($InAnnotations_Class) {
                            $TypeAttr{"Annotations"}{registerType($AName, $LVer)} = 1;
                        }
                        elsif($InAnnotations_Method) {
                            $MethodInfo{$LVer}{$MName_Mid{$CurrentMethod}}{"Annotations"}{registerType($AName, $LVer)} = 1;
                        }
                    }
                    else
                    { # suport for Java 7
                        $AnnotationNum{$1} = 1;
                    }
                }
            }
        }
        elsif($CurrentMethod and $InParamTable==1 and $LINE=~/\A\s+0\s+\d+\s+\d+\s+(\#?)(\w+)/)
        { # read parameter names from LocalVariableTable
            my $Art = $1;
            my $PName = $2;
            
            if(($PName ne "this" or $Art) and $PName=~/[a-z]/i)
            {
                if($CurrentMethod)
                {
                    my $ID = $MName_Mid{$CurrentMethod};
                    
                    if(defined $MethodInfo{$LVer}{$ID}
                    and defined $MethodInfo{$LVer}{$ID}{"Param"}
                    and defined $MethodInfo{$LVer}{$ID}{"Param"}{$ParamPos}
                    and defined $MethodInfo{$LVer}{$ID}{"Param"}{$ParamPos}{"Type"})
                    {
                        $MethodInfo{$LVer}{$ID}{"Param"}{$ParamPos}{"Name"} = $PName;
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
            $InAnnotations_Method = 1;
            $InAnnotations_Class = 0;
            
            ($MethodAttr{"Return"}, $MethodAttr{"ShortName"}, $ParamsLine, $Exceptions) = ($2, $3, $4, $6);
            $MethodAttr{"ShortName"}=~s/#/./g;
            
            if($Exceptions)
            {
                foreach my $E (split(/,/, $Exceptions)) {
                    $MethodAttr{"Exceptions"}{registerType($E, $LVer)} = 1;
                }
            }
            if($LINE=~/(\A|\s+)(public|protected|private)\s+/) {
                $MethodAttr{"Access"} = $2;
            }
            else {
                $MethodAttr{"Access"} = "package-private";
            }
            $MethodAttr{"Class"} = registerType($TypeAttr{"Name"}, $LVer);
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
                $MethodAttr{"Return"} = registerType($MethodAttr{"Return"}, $LVer);
            }
            
            my @Params = sepParams($ParamsLine, 0, 1);
            
            $ParamPos = 0;
            foreach my $ParamTName (@Params)
            {
                %{$MethodAttr{"Param"}{$ParamPos}} = ("Type"=>registerType($ParamTName, $LVer), "Name"=>"p".($ParamPos+1));
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
            if($LINE_N=~/(Signature|descriptor):\s*(.+)\Z/i)
            { # create run-time unique name ( java/io/PrintStream.println (Ljava/lang/String;)V )
                if($MethodAttr{"Constructor"}) {
                    $CurrentMethod = $CurrentClass.".\"<init>\":".$2;
                }
                else {
                    $CurrentMethod = $CurrentClass.".".$MethodAttr{"ShortName"}.":".$2;
                }
                if(my $PackageName = getSFormat($CurrentPackage)) {
                    $CurrentMethod = $PackageName."/".$CurrentMethod;
                }
                
                $LineNum++;
            }
            else {
                exitStatus("Error", "internal error - can't read method signature");
            }
            
            $MethodAttr{"Archive"} = $ArchiveName;
            if($CurrentMethod)
            {
                my $ID = undef;
                if($In::Opt{"Reproducible"}) {
                    $ID = getMd5($CurrentMethod);
                }
                else {
                    $ID = ++$M_ID;
                }
                
                $MName_Mid{$CurrentMethod} = $ID;
                
                if(defined $Mid_MName{$ID} and $Mid_MName{$ID} ne $CurrentMethod) {
                    printMsg("ERROR", "md5 collision on \'$ID\', please increase ID length (MD5_LEN in Basic.pm)");
                }
                
                $Mid_MName{$ID} = $CurrentMethod;
                
                $MethodAttr{"Name"} = $CurrentMethod;
                $MethodInfo{$LVer}{$ID} = \%MethodAttr;
            }
        }
        elsif($CurrentClass and $LINE=~/(\A|\s+)([^\s]+)\s+(\w+);\Z/)
        { # fields
            my ($TName, $FName) = ($2, $3);
            $TypeAttr{"Fields"}{$FName}{"Type"} = registerType($TName, $LVer);
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
            if($LINE=~/(\A|\s+)(public|protected|private)\s+/) {
                $TypeAttr{"Fields"}{$FName}{"Access"} = $2;
            }
            else {
                $TypeAttr{"Fields"}{$FName}{"Access"} = "package-private";
            }
            
            $TypeAttr{"Fields"}{$FName}{"Pos"} = $FieldPos++;
            
            # read the Signature
            if($Content[$LineNum++]=~/(Signature|descriptor):\s*(.+)\Z/i)
            {
                my $FSignature = $2;
                if(my $PackageName = getSFormat($CurrentPackage)) {
                    $TypeAttr{"Fields"}{$FName}{"Mangled"} = $PackageName."/".$CurrentClass.".".$FName.":".$FSignature;
                }
            }
            if($Content[$LineNum]=~/flags:/i)
            { # flags: ACC_PUBLIC, ACC_STATIC, ACC_FINAL, ACC_ANNOTATION
                $LineNum++;
            }
            
            # read the Value
            if($Content[$LineNum]=~/Constant\s*value:\s*([^\s]+)\s(.*)\Z/i)
            {
              # Java 6: Constant value: ...
              # Java 7: ConstantValue: ...
                $LineNum+=1;
                my ($TName, $Value) = ($1, $2);
                if($Value)
                {
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
            if($TypeAttr{"Name"})
            { # register previous
                %{$TypeInfo{$LVer}{registerType($TypeAttr{"Name"}, $LVer)}} = %TypeAttr;
            }
            
            %TypeAttr = ("Type"=>$2, "Name"=>$3); # reset previous class
            %AnnotationName = (); # reset annotations of the class
            %AnnotationNum = (); # support for Java 7
            $InAnnotations_Class = 1;
            
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
            if($LINE=~/(\A|\s+)(public|protected|private)\s+/) {
                $TypeAttr{"Access"} = $2;
            }
            else {
                $TypeAttr{"Access"} = "package-private";
            }
            if($LINE=~/\s+extends\s+([^\s\{]+)/)
            {
                my $Extended = $1;
                
                if($TypeAttr{"Type"} eq "class")
                {
                    if($Extended ne $CurrentPackage.".".$CurrentClass) {
                        $TypeAttr{"SuperClass"} = registerType($Extended, $LVer);
                    }
                }
                elsif($TypeAttr{"Type"} eq "interface")
                {
                    my @Elems = sepParams($Extended, 0, 0);
                    foreach my $SuperInterface (@Elems)
                    {
                        if($SuperInterface ne $CurrentPackage.".".$CurrentClass) {
                            $TypeAttr{"SuperInterface"}{registerType($SuperInterface, $LVer)} = 1;
                        }
                        
                        if($SuperInterface eq "java.lang.annotation.Annotation") {
                            $TypeAttr{"Annotation"} = 1;
                        }
                    }
                }
            }
            if($LINE=~/\s+implements\s+([^\s\{]+)/)
            {
                my $Implemented = $1;
                my @Elems = sepParams($Implemented, 0, 0);
                
                foreach my $SuperInterface (@Elems) {
                    $TypeAttr{"SuperInterface"}{registerType($SuperInterface, $LVer)} = 1;
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
        elsif(index($LINE, "Deprecated: true")!=-1
        or index($LINE, "Deprecated: length")!=-1)
        { # deprecated method or class
            if($CurrentMethod) {
                $MethodInfo{$LVer}{$MName_Mid{$CurrentMethod}}{"Deprecated"} = 1;
            }
            elsif($CurrentClass) {
                $TypeAttr{"Deprecated"} = 1;
            }
        }
        elsif(index($LINE, "RuntimeInvisibleAnnotations")!=-1
        or index($LINE, "RuntimeVisibleAnnotations")!=-1)
        {
            $InAnnotations = 1;
            $InCode = 0;
        }
        elsif(defined $InAnnotations and index($LINE, "InnerClasses")!=-1) {
            $InAnnotations = undef;
        }
        else
        {
            # unparsed
        }
    }
    if($TypeAttr{"Name"})
    { # register last
        %{$TypeInfo{$LVer}{registerType($TypeAttr{"Name"}, $LVer)}} = %TypeAttr;
    }
}

sub registerType($$)
{
    my ($TName, $LVer) = @_;
    
    if(not $TName) {
        return 0;
    }
    
    $TName=~s/#/./g;
    if($TName_Tid{$LVer}{$TName}) {
        return $TName_Tid{$LVer}{$TName};
    }
    
    if(not $TName_Tid{$LVer}{$TName})
    {
        my $ID = undef;
        if($In::Opt{"Reproducible"}) {
            $ID = getMd5($TName);
        }
        else {
            $ID = ++$T_ID;
        }
        $TName_Tid{$LVer}{$TName} = "$ID";
    }
    
    my $Tid = $TName_Tid{$LVer}{$TName};
    $TypeInfo{$LVer}{$Tid}{"Name"} = $TName;
    if($TName=~/(.+)\[\]\Z/)
    {
        if(my $BaseTypeId = registerType($1, $LVer))
        {
            $TypeInfo{$LVer}{$Tid}{"BaseType"} = $BaseTypeId;
            $TypeInfo{$LVer}{$Tid}{"Type"} = "array";
        }
    }
    
    return $Tid;
}

sub readClasses_Usage($)
{
    my $Paths = $_[0];
    
    my $JavapCmd = getCmdPath("javap");
    if(not $JavapCmd) {
        exitStatus("Not_Found", "can't find \"javap\" command");
    }
    
    my $Input = join(" ", @{$Paths});
    if($In::Opt{"OS"} ne "windows")
    { # on unix ensure that the system does not try and interpret the $, by escaping it
        $Input=~s/\$/\\\$/g;
    }
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    chdir($TmpDir."/".$ExtractCounter);
    open(CONTENT, "$JavapCmd -c -private $Input 2>\"$TmpDir/warn\" |");
    while(<CONTENT>)
    {
        if(/\/\/\s*(Method|InterfaceMethod)\s+(.+)\Z/)
        {
            my $M = $2;
            $In::Opt{"UsedMethods_Client"}{$M} = 1;
            
            if($M=~/\A(.*)+\.\w+\:\(/)
            {
                my $C = $1;
                $C=~s/\//./g;
                $In::Opt{"UsedClasses_Client"}{$C} = 1;
            }
        }
        elsif(/\/\/\s*Field\s+(.+)\Z/)
        {
            # my $FieldName = $1;
            # if(/\s+(putfield|getfield|getstatic|putstatic)\s+/) {
            #     $UsedFields_Client{$FieldName} = $1;
            # }
        }
        elsif(/ ([^\s]+) [^: ]+\(([^()]+)\)/)
        {
            my ($Ret, $Params) = ($1, $2);
            
            $Ret=~s/\[\]//g; # quals
            $In::Opt{"UsedClasses_Client"}{$Ret} = 1;
            
            foreach my $Param (split(/\s*,\s*/, $Params))
            {
                $Param=~s/\[\]//g; # quals
                $In::Opt{"UsedClasses_Client"}{$Param} = 1;
            }
        }
        elsif(/ class /)
        {
            if(/extends ([^\s{]+)/)
            {
                foreach my $Class (split(/\s*,\s*/, $1)) {
                    $In::Opt{"UsedClasses_Client"}{$Class} = 1;
                }
            }
            
            if(/implements ([^\s{]+)/)
            {
                foreach my $Interface (split(/\s*,\s*/, $1)) {
                    $In::Opt{"UsedClasses_Client"}{$Interface} = 1;
                }
            }
        }
    }
    close(CONTENT);
    chdir($In::Opt{"OrigDir"});
}

return 1;
