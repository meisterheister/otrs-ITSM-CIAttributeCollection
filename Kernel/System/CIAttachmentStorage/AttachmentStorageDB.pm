# --
# Kernel/System/CIAttachmentStorage/AttachmentStorageDB.pm - attachment storage in local data base
# Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Torsten(dot)Thau(at)cape-it(dot)de
# * Anna(dot)Litvinova(at)cape-it(dot)de
# * Anna(dot)Litvinova(at)cape(dash)it(dot)de
# * Torsten(dot)Thau(at)cape(dash)it(dot)de
# * Mario(dot)Illinger(at)cape(dash)it(dot)de
#
# --
# $Id: AttachmentStorageDB.pm,v 1.11 2016/05/18 07:40:47 tto Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CIAttachmentStorage::AttachmentStorageDB;

use strict;
use warnings;

use MIME::Base64;
use Digest::MD5 qw(md5_hex);

our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::Encode',
    'Kernel::System::Log'
);

=head1 NAME

Kernel::System::CIAttachmentStorage::AttachmentStorageDB

=head1 SYNOPSIS

Provides attachment handling for data base backend - local, OTRS-data base.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create AttachmentStorageDB object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $AttachmentObject = $Kernel::OM->Get('Kernel::System::CIAttachmentStorage::AttachmentStorageDB');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{DBObject}     = $Kernel::OM->Get('Kernel::System::DB');
    $Self->{EncodeObject} = $Kernel::OM->Get('Kernel::System::Encode');
    $Self->{LogObject}    = $Kernel::OM->Get('Kernel::System::Log');

    return $Self;
}

=item AttachmentAdd()

create a new std. attachment

    my $ID = $AttachmentObject->AttachmentAdd(
        AttDirID => 123,
        DataRef  => \$SomeContent,
    );

=cut

sub AttachmentAdd {
    my ( $Self, %Param ) = @_;
    my $ID = 0;

    #check required stuff...
    foreach (qw(AttDirID DataRef)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
            return;
        }
    }

    #encode attachment if it's a postgresql backend...
    if ( !$Self->{DBObject}->GetDatabaseFunction('DirectBlob') ) {
        $Self->{EncodeObject}->EncodeOutput( $Param{DataRef} );

        #overwrite existing value instead of using another filesize of memory...
        ${ $Param{DataRef} } = encode_base64( ${ $Param{DataRef} } );
    }

    #db quoting...
    foreach (qw( AttDirID)) {
        $Param{$_} = $Self->{DBObject}->Quote( $Param{$_}, 'Integer' );
    }

    #build sql...
    my $SQL = "";
    if ( $Self->{DBObject}->{Backend}->{'DB::Type'} =~ /oracle/ ) {
        $SQL = "INSERT INTO attachment_storage " .
            " (attachment_directory_id, data) " .
            " VALUES " .
            " ( $Param{AttDirID}, EMPTY_CLOB())";

    }
    else {
        $SQL = "INSERT INTO attachment_storage " .
            " (attachment_directory_id, data) " .
            " VALUES " .
            " ( $Param{AttDirID}, ?)";
    }

    #run sql...
    my $DoResult = 0;
    $DoResult = $Self->{DBObject}->Do(
        SQL => $SQL, Bind => [ $Param{DataRef} ],    # AttDirID => $Param{AttDirID}
    );

    if ($DoResult) {

        #return ID...
        $Self->{DBObject}->Prepare(
            SQL => "SELECT id FROM attachment_storage WHERE " .
                "attachment_directory_id = $Param{AttDirID}",
        );
        while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
            $ID = $Row[0];
        }
        return $ID;
    }
    else {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message => "Failed to insert attachment data!"
        );
        return;
    }
}

=item AttachmentGet()

returns an entry in attachment_storage

    my %Data = $AttachmentObject->AttachmentGet(
        ID => 123, #(some attachment storage id)
        # ...OR...
        AttDirID => 123 #(some attachment directory id),
    );
=cut

sub AttachmentGet {
    my ( $Self, %Param ) = @_;
    my %Data  = ();
    my $WHERE = "";

    #check required stuff...
    if ( !$Param{ID} && !$Param{AttDirID} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => "Need AttDirID or ID!" );
        return \%Data;
    }

    #db quoting...
    foreach (qw( AttDirID ID)) {
        $Param{$_} = $Self->{DBObject}->Quote( $Param{$_}, 'Integer' );
    }

    #build sql...
    if ( defined( $Param{AttDirID} ) && $Param{AttDirID} ) {
        $WHERE = " WHERE attachment_directory_id = $Param{AttDirID}";
    }
    else {
        $WHERE = " WHERE id = $Param{ID}";
    }

    my $SQL = "SELECT id, attachment_directory_id FROM attachment_storage " . $WHERE;

    if ( !$Self->{DBObject}->Prepare( SQL => $SQL, Encode => [ 0, 0, 1 ] ) ) {
        return \%Data;
    }

    my @Data = $Self->{DBObject}->FetchrowArray();

    if (@Data) {
        my $SQL = "SELECT data FROM attachment_storage " . $WHERE;

        if ( !$Self->{DBObject}->Prepare( SQL => $SQL ) ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Failed to prepare SQL for FetchrowArray!"
            );
            return \%Data;
        }

        my @AttachData = $Self->{DBObject}->FetchrowArray();

        my $AttachDataRef = \$AttachData[0];

        if ( !$AttachDataRef ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Failed to FetchrowArray!"
            );
            return \%Data;
        }

        #decode attachment if it's a postgresql backend...
        if ( !$Self->{DBObject}->GetDatabaseFunction('DirectBlob') ) {
            ${$AttachDataRef} = decode_base64( ${$AttachDataRef} );
        }

        %Data = (
            ID       => $Data[0],
            AttDirID => $Data[1],

            DataRef => $AttachDataRef,
        );

        $AttachDataRef = undef;
    }

    return \%Data;
}

=item AttachmentGetRealProperties()

returns the size of the attachment in the storage backend and the md5sum.

    my RealProperties = AttachmentStorageObject->AttachmentGetRealProperties(
        AttDirID => 123, #(some attachment directory id)
        #..OR...
        ID => 123, #(some attachment storage id)
    );

=cut

sub AttachmentGetRealProperties {
    my ( $Self, %Param ) = @_;

    my %RealProperties;

    #check required stuff...
    if ( !$Param{AttDirID} ) {
        $Self->{LogObject}->Log( Priority => 'error', Message => "Need AttDirID!" );
        return %RealProperties;
    }

    my $Data = $Self->AttachmentGet(
        AttDirID => $Param{AttDirID}
    );

    my $RealFileSize = 0;
    my $RealMD5Sum   = '';

    if ( defined $Data && $Data->{DataRef} ) {
        my $Content = ${ $Data->{DataRef} };
        $Self->{EncodeObject}->EncodeOutput( \$Content );

        $RealFileSize = bytes::length($Content);
        $RealMD5Sum   = md5_hex($Content);
    }

    $RealProperties{RealFileSize} = $RealFileSize;
    $RealProperties{RealMD5Sum}   = $RealMD5Sum;

    return %RealProperties;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (http://otrs.org/).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see http://www.gnu.org/licenses/agpl.txt.

=cut