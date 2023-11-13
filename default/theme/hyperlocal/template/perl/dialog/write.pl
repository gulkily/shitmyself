#!/usr/bin/perl -T

use strict;
use warnings;
use 5.010;
use utf8;

sub GetWriteDialog {
# sub GetWriteWindow {

	WriteLog('GetWriteDialog: hyperlocal theme');

	my $dialogTitle = shift;
	if (!$dialogTitle) {
		$dialogTitle = 'Write';
	} else {
		#todo sanity check
	}

	my $formWrite = GetWriteForm();

	my $dialog = GetDialogX($formWrite, $dialogTitle);

#	 style="background-image:url(http://www.hypercode.com/hypercode_bg.jpg)"
#    <p><b>You have selected <u>hypercode.com</u> as your publish node.</b></p>


	return $dialog;
} # GetWriteDialog()

sub GetWriteForm { # $dialogTitle ; returns write form (for composing text message)
# sub GetWriteForm {
	# renamed so that old references which assumed it is a dialog break and can be fixed

	#
	# my $prompt = shift;
	# if (!$prompt) {
	# 	$prompt = 'Write something here:';
	# } else {
	# 	#todo sanity check
	# }

	#my $writeForm = GetDialogX(GetTemplate('html/form/write/write.template'), $dialogTitle);
	my $writeForm = GetTemplate('html/form/write/write.template');
	$writeForm = str_replace('<!-- ATTENTION: this template is updated by MakeWritePage() -->', '', $writeForm); #UtilityComment
	# my $writeForm = GetDialogX(GetTemplate('html/form/write/write.template'), 'Write');
	#WriteLog('GetWriteForm: $dialogTitle = ' . $dialogTitle . '; caller = ' . join(',', caller));

	# if ($prompt ne 'Write something here:') { #todo templatize this
	# 	$writeForm = str_replace('Writek something here:', $prompt, $writeForm);
	# }

	if (GetConfig('admin/php/enable')) {
		WriteLog('GetWriteForm: php is ON');
		my $writeLongMessage = GetTemplate('html/form/write/long_message.template');
		if ($writeLongMessage) {
			my $targetElement = '<span id=writefooter>';
			$writeForm = str_replace($targetElement, $targetElement . $writeLongMessage, $writeForm);
		}

		# if (GetConfig('admin/php/enable') && !GetConfig('admin/php/rewrite')) {
		# 	# if php is enabled but rewrite is disabled
		# 	# change submit target to post.php
		# 	#my $postHtml = 'post.html'; # post.html
		# 	WriteLog('GetWriteForm: replacing post.html post.php');
		# 	$writeForm = str_replace('/post.html', '/post.php', $writeForm);
		# 	#$writeForm =~ s/$postHtml/post.php/;
		# } else {
		# 	WriteLog('GetWriteForm: NOT replacing post.html post.php');
		# }

		# this is how auto-save to server would work (with privacy implications) #autosave
		# $submitForm =~ s/\<textarea/<textarea onkeyup="if (this.length > 2) { document.forms['compose'].action='\/post2.php'; }" /;
	} else {
		WriteLog('GetWriteForm: php is OFF');
	}

	my $postPath = GetTargetPath('post'); #todo should this use config/setting/admin/post/post_url?

	if ($postPath eq '/post.html') {
		# don't need to replace
		WriteLog('GetWriteForm: no need to replace /post.html');
	} else {
		WriteLog('GetWriteForm: replacing /post.html with $postPath = ' . $postPath);
		$writeForm = str_replace('/post.html', $postPath, $writeForm);
	}

	my $initText = '';
	$writeForm =~ s/\$initText/$initText/g;

	if (GetConfig('admin/js/enable')) {
		# javascript is enabled, add event hooks
		my $writeOnChange = "if (window.CommentOnChange) { return CommentOnChange(this, 'compose'); } else { return true; }";
		$writeForm = AddAttributeToTag($writeForm, 'textarea', 'onchange', $writeOnChange);
		$writeForm = AddAttributeToTag($writeForm, 'textarea', 'onkeyup', $writeOnChange);
		if (GetConfig('admin/js/translit')) {
			$writeForm = AddAttributeToTag(
				$writeForm,
				'textarea',
				'onkeydown',
				'if (window.translitKey) { translitKey(event, this); } else { return true; }'
			);
		}

		if (GetConfig('admin/js/write_form_optimize_for_delivery')) {
			$writeForm = AddAttributeToTag(
				$writeForm,
				'input type=submit',
				'onclick',
				"this.value = 'Meditate...'; if (window.WriteSubmit) { setTimeout('WriteSubmit();', 100); return true; } else { return true; }" #write #optimize_for_delivery = true
			);
		} else {
			$writeForm = AddAttributeToTag(
				$writeForm,
				'input type=submit',
				'onclick',
				"this.value = 'Meditate...'; if (window.WriteSubmit) { return WriteSubmit(); } else { return true; }" #write #optimize_for_delivery = false
			);
		}
	} # js stuff in write form

	{ # a hack, only for overlaying chicago theme
		$writeForm = str_replace('<span id=writefooter></span>', '<span id=writefooter><p><b>You have selected <u>hypercode.com</u> as your publish node.</b></p></span>', $writeForm);
		$writeForm = AddAttributeToTag('table id=write', 'style', 'background-image:url(http://www.hypercode.com/hypercode_bg.jpg)', $writeForm);
		$writeForm = str_replace('bgcolor="#c0c0c0"', 'bgcolor="#fff0ef"', $writeForm);
		$writeForm = str_replace('<form action="/post.html"', '<form action="http://www.hypercode.com/post.html"', $writeForm);
	}

	$writeForm = 'hey';

	return $writeForm;
} # GetWriteForm()

1;