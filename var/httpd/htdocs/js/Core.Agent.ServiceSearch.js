// --
// Core.Agent.ServiceSearch.js - provides the special module functions for the service search
// Copyright (C) 2006-2011 c.a.p.e. IT GmbH, http://www.cape-it.de
//
// written/edited by:
//   Frank(dot)Oberender(at)cape(dash)it(dot)de
//   Martin(dot)Balzarek(at)cape(dash)it(dot)de
//
// --
// $Id: Core.Agent.ServiceSearch.js,v 1.4 2016/05/27 13:23:06 fjacquemin Exp $
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace
 * @exports TargetNS as Core.Agent.ServiceSearch
 * @description
 *      This namespace contains the special module functions for the service search.
 */
Core.Agent.ServiceSearch = (function (TargetNS) {

   /**
     * @function
     * @param {jQueryObject} $Element The jQuery object of the input field with autocomplete
     * @param {Boolean} ActiveAutoComplete Set to false, if autocomplete should only be started by click on a button next to the input field
     * @return nothing
     *      This function initializes the special module functions
     */
    TargetNS.Init = function ($Element, ActiveAutoComplete) {
        var FieldID = $Element.attr('id').replace(/:/g, '\\:');

        if (typeof ActiveAutoComplete === 'undefined') {
            ActiveAutoComplete = true;
        }
        else {
            ActiveAutoComplete = !!ActiveAutoComplete;
        }
        if (isJQueryObject($Element)) {
            $Element.autocomplete({
                minLength: ActiveAutoComplete ? Core.Config.Get('Autocomplete.MinQueryLength') : 500,
                delay: Core.Config.Get('Autocomplete.QueryDelay'),
                source: function (Request, Response) {
                    var URL = Core.Config.Get('Baselink'), Data = {
                        Action: 'AgentServiceSearch',
                        Term: Request.term,
                        MaxResults: Core.Config.Get('Autocomplete.MaxResultsDisplayed')
                    };
                    console.log(URL);
                    Core.AJAX.FunctionCall(URL, Data, function (Result) {
                        var Data = [];
                        $.each(Result, function () {
                            Data.push({
                                label: this.ServiceValue + " (" + this.ServiceKey + ")",
                                value: this.ServiceValue
                            });
                        });
                        Response(Data);
                    });
                },
                select: function (Event, UI) {
                    var ServiceKey = UI.item.label.replace(/.*\((.*)\)$/, '$1');

                    $Element.val(UI.item.value);

                    // set hidden field SelectedService
                    $('#' + FieldID + 'Selected').val(ServiceKey);

                    Event.preventDefault();
                    return false;
                }
            });

            if (!ActiveAutoComplete) {
                $Element.after('<button id="' + $Element.attr('id') + 'Search" type="button">' + Core.Config.Get('Autocomplete.SearchButtonText') + '</button>');
                $('#' + FieldID + 'Search').click(function () {
                    $Element.autocomplete("option", "minLength", 0);
                    $Element.autocomplete("search");
                    $Element.autocomplete("option", "minLength", 500);
                });
            }
        }

        // On unload remove old selected data. If the page is reloaded (with F5) this data stays in the field and invokes an ajax request otherwise
        $(window).bind('unload', function () {
           $('#' + FieldID + 'Selected').val('');
        });
    };

    return TargetNS;
}(Core.Agent.ServiceSearch || {}));
