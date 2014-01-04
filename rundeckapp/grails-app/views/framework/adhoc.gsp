<%@ page import="grails.util.Environment; rundeck.User; com.dtolabs.rundeck.server.authorization.AuthConstants" %>
<html>
<head>
    <g:set var="ukey" value="${g.rkey()}" />
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
    <meta name="layout" content="base"/>
    <meta name="tabpage" content="adhoc"/>
    <title><g:message code="gui.menu.Nodes"/> - ${session.project.encodeAsHTML()}</title>
    <g:javascript library="executionControl"/>
    <g:javascript library="yellowfade"/>
    <g:javascript library="pagehistory"/>
    <g:if test="${grails.util.Environment.current == Environment.DEVELOPMENT}">
        <g:javascript src="knockout-3.0.0.debug.js"/>
    </g:if>
    <g:else>
        <g:javascript src="knockout-3.0.0-min.js"/>
    </g:else>
    <g:javascript src="knockout.mapping-latest.js"/>
    <g:javascript src="moment.min.js"/>
    <asset:javascript src="momentutil.js"/>
    <g:javascript src="historyKO.js"/>
    <g:set var="defaultLastLines" value="${grailsApplication.config.rundeck.gui.execution.tail.lines.default}"/>
    <g:set var="maxLastLines" value="${grailsApplication.config.rundeck.gui.execution.tail.lines.max}"/>
    <script type="text/javascript">
        function showError(message) {
            $("error").innerHTML += message;
            $("error").show();
        }

        /**
         * START run execution code
         */
        <g:set var="filterParams" value="${query?.properties.findAll{it.key==~/^(node(In|Ex)clude.*|project)$/ &&it.value}}"/>

        var nodeFilterData_${ukey}=${filterParams.encodeAsJSON()};
        var nodespage=0;
        var pagingMax=20;
        function expandResultNodes(page,elem){
            if(!page){
                page=0;
            }
            nodespage=page;
            if(!elem){
                elem='nodelist';
            }
            var view=page==0?'table':'tableContent';
            _updateMatchedNodes(nodeFilterData_${ukey},elem,'${session.project}',false,{view:view,expanddetail:true,inlinepaging:true,page:page,max:pagingMax});
        }
        function _loadNextNodesPageTable(max,total,tbl,elem){
            if(!nodespage){
                nodespage=0;
            }
            var next=nodespage+1;
            if(total<0 || max*next<total){
                //create sibling of elem
                var div= new Element('tbody');
                $(tbl).insert({bottom:div});
                //total < 0 means load all remaining, so invert next page
                expandResultNodes(next* (total<0?-1:1),Element.identify(div));
            }
//            console.log("next: "+(max*(next+1))+", total: "+total);
            var loadCount = max*(next+1);
            if(loadCount>=total || total<0){
                //hide pager button area
                $(elem).hide();
            }else{
                //update moreCount
                $('moreCount').innerHTML=total-loadCount;
                if(total-loadCount<max){
                    $('nextPageButton').hide();
                }
            }
        }
        var _runBtnHtml;
        function disableRunBar(){
            if($('runbox')){
                $('runbox').down('input[type="text"]').disable();
                if ($('runbox').down('button.runbutton')) {
                    $('runbox').down('button.runbutton').disabled = true;
                    $('runbox').down('button.runbutton').addClassName('disabled');
                    _runBtnHtml= $('runbox').down('button.runbutton').innerHTML;
                    $('runbox').down('button.runbutton').innerHTML="Running…";
                }
            }
        }
        function enableRunBar(){
            if ($('runbox')) {
                $('runbox').down('input[type="text"]').enable();
                if($('runbox').down('button.runbutton')){
                    $('runbox').down('button.runbutton').disabled=false;
                    $('runbox').down('button.runbutton').removeClassName('disabled');
                    $('runbox').down('button.runbutton').innerHTML = 'Run <span class="glyphicon glyphicon-play"></span>';
                }
            }
        }
        function collapseNodeView(){
//            $$('.obs_shownodes').each(Element.show);
            $$('.obs_shownodes').each(function(e){Expander.close(e,null);});

            $$('.nodeview').each(Element.hide);
            $$('.nodeviewsummary').each(Element.show);
        }
        function showNodeView(){
//            $$('.obs_shownodes').each(Element.hide);
            $$('.obs_shownodes').each(function(e){Expander.open(e,null);});
            $$('.nodeview').each(Element.show);
            $$('.nodeviewsummary').each(Element.hide);
        }
        function runStarted(){
            running=true;
            $$('.hiderun').each(Element.hide);
            $$('.showrun').each(Element.show);
            collapseNodeView();
        }
        function afterRun(){
            running=false;
            $$('.showafterrun').each(Element.show);
            $$('.hideafterrun').each(Element.hide);
            $('runFormExec').focus();
        }
        function runError(msg){
            $('runerror').innerHTML=msg;
            $('runerror').show();
            $('runcontent').hide();
            onRunComplete();
        }
        function requestFailure(trans){
            runError("Request failed: "+trans.statusText);
        }
        var running=false;
        /**
         * Run the command
         * @param elem
         */
        function runFormSubmit(elem){
            if(running || !$F('runFormExec')){
                return false;
            }
            var data = Form.serialize(elem);
            disableRunBar();
            runStarted();
            $('runcontent').loading('Starting Execution&hellip;');
            new Ajax.Request("${createLink(controller:'scheduledExecution',action:'runAdhocInline')}",{
                parameters:data,
                evalScripts:true,
                evalJSON:true,
                onSuccess: function(transport) {
                    var data =transport.responseJSON;
//                    alert("data: "+data);
                    try{
                    startRunFollow(data);
                    }catch(e){
                        console.log(e);
                        runError(e);
                    }
                },
                onFailure:requestFailure
            });
            return false;
        }
        /**
         * Load content view to contain output
         * @param data
         */
        function startRunFollow(data){
            if(data.error){
                runError(data.error);
            }else if(!data.id){
                runError("Server response was invalid: "+data.toString());
            }else {
                $('runcontent').loading('Loading Output&hellip;');
                new Ajax.Updater('runcontent',"${createLink(controller:'execution',action:'followFragment')}",{
                parameters:{id:data.id,mode:'tail'},
                evalScripts:true,
                onComplete: function(transport) {
                    if (transport.request.success()) {
                        Element.show('runcontent');
//                        try{
                        continueRunFollow(data);
//                        }catch(e){
//                            console.log(e,e);
//                            runError(e);
//                        }
                    }
                },
                onFailure:requestFailure
            });
            }
        }
        /**
         * Start following the output
         * @param data
         */
        function continueRunFollow(data){
             var followControl = new FollowControl(data.id,'runcontent',{
                 parentElement: 'commandPerform',
                 viewoptionsCompleteId: 'viewoptionscomplete',
                 cmdOutputErrorId: 'cmdoutputerror',
                 outfileSizeId: 'outfilesize',
                extraParams:"<%="true" == params.disableMarkdown ? '&disableMarkdown=true' : ''%>",
                smallIconUrl: "${resource(dir: 'images', file: 'icon-small')}",
                iconUrl: "${resource(dir: 'images', file: 'icon-small')}",
                lastlines: ${params.lastlines ? params.lastlines : defaultLastLines},
                maxLastLines: ${maxLastLines},
                 showFinalLine: {value: false, changed: false},
                 colStep:{value:false},
                tailmode: true,
                 taildelay:1,
                 truncateToTail:true,
                execData: {node:"test"},
                appLinks:appLinks,
                onComplete:onRunComplete,
                dobind:true
            });
            followControl.beginFollowingOutput(data.id);
        }
        function onRunComplete(){
            enableRunBar();
            afterRun();
        }

        /**
         * START tag filter link code
         */
        function setTagFilter(value){
            if($('schedJobNodeIncludeTags').value){
                $('schedJobNodeIncludeTags').value+=","+value;
            }else{
                $('schedJobNodeIncludeTags').value=value;

            }
            $('${ukey}filter').down('form').submit();
        }


        /**
         * Handle embedded content updates
         */
        function _updateBoxInfo(name,data){
            if(name=='nodes'){
                if(data.total && data.total!="0"){
                    enableRunBar();
                }else{
                    disableRunBar();
                }
                if(null !=data.total){
                    $$('.obs_nodes_page_total').each(function(e){
                        e.innerHTML=data.total;
                    });
                    $$('.obs_nodes_allcount').each(function(e){
                        e.innerHTML=data.total;
                    });
                    $$('.obs_nodes_allcount_plural').each(function (e) {
                        e.innerHTML = data.total == 1 ? '' : 's';
                    });
                }
            }
        }

        function _matchNodes(){
            //use form field
            jQuery('.nodefilterlink').removeClass('active');
            loadNodeFilter(null,jQuery('#schedJobNodeFilter').val());
        }
        function setNodeFilterLink(e){
            jQuery('.nodefilterlink').removeClass('active');
            jQuery(e).addClass('active');
            var filterName = jQuery(e).data('node-filter-name');
            var filterString = jQuery(e).data('node-filter');
            loadNodeFilter(filterName,filterString);
        }
        function setNodeFilterLinkAction(result){
            result.find('.nodefilterlink').click(function (evt) {
                evt.preventDefault();
                setNodeFilterLink(this);
            });
        }
        function loadNodeFilter(filterName, filterString){
            var completion = function (data) {
                jQuery("#${ukey}nodeForm").html(data.responseText);
                jQuery('#hiddenNodeFilter').val(filterString?filterString:'');
                jQuery('#schedJobNodeFilter').val(filterString?filterString:'');
                jQuery('#hiddenNodeFilterName').val(filterName?filterName:'');
                setNodeFilterLinkAction(jQuery('#${ukey}nodeForm'));
            };
            if(filterString){
                var filter= filterString;
                jQuery.get("${g.createLink(controller: 'framework',action: 'nodesFragment',params: [maxShown:10,requireRunAuth:'true',project: session.project, view:'embed'])}&filter="+(encodeURIComponent(filter)))
                        .complete(completion);
            }else if(filterName){
                jQuery.get("${g.createLink(controller: 'framework',action: 'nodesFragment',params: [maxShown:10,requireRunAuth:'true',project: session.project, view:'embed'])}&filterName=" + (encodeURIComponent(filterName)))
                        .complete(completion);
            }
        }

        function loadFilterPresets(){
            jQuery.get("${g.createLink(controller: 'framework',action: 'nodeFilterPresets',params:[projFilter: session.project])}").complete(function(data){
                jQuery("#filterPresets").html(data.responseText);
                setNodeFilterLinkAction(jQuery('#filterPresets'));
            });
        }

        /**
         * START page init
         */
        function init() {
            jQuery('.act_showinlinenodefilter').click(function(e){
                //load filters/tags
                loadFilterPresets();

            });
            jQuery('.act_setinlinenodefilter').click(function (e) {
                //apply new filter
                _matchNodes();
            });
            setNodeFilterLinkAction(jQuery('#${ukey}nodeForm'));
            $$('#runbox input').each(function(elem){
                if(elem.type=='text'){
                    elem.observe('keypress',function(evt){
                        if(!noenter(evt)){
                            runFormSubmit('runbox');
                            return false;
                        }else{
                            return true;
                        }
                    });
                }
            });
            var ajaxHistoryLink="${g.createLink(controller: 'reports', action: 'eventsAjax', absolute: true)}";
            var history = new History(ajaxHistoryLink);
            ko.applyBindings(history, document.getElementById('activity_section'));
            setupActivityLinks('activity_section', history, ajaxHistoryLink);

            //if empty query, automatically load first activity_link
            if("${emptyQuery}"=='true'){
                jQuery('ul.activity_links > li:first-child').addClass('active');
                jQuery('ul.activity_links > li:first-child > a').each(function(e){
                    loadHistoryLink(history, ajaxHistoryLink, this.getAttribute('href'));
                });
            }
        }
        jQuery(document).ready(init);

    </script>
    <style type="text/css">
        #runerror{
            color:red;
            margin:5px 20px;
        }

        .commandcontent{
            margin:0;
        }

        table.execoutput {
            font-size: 100%;
        }
        #nodesPaging{
            margin-top:5px;
        }
    </style>
</head>
<body>

<div id="nodesContent">
    <g:set var="run_authorized" value="${auth.adhocAllowedTest( action:AuthConstants.ACTION_RUN)}"/>


    <g:render template="/common/messages"/>
    <div id="error" class="error message" style="display:none;"></div>
        <div>
            <div class="row ">
                <g:if test="${run_authorized}">
                    <div class=" form-inline clearfix" id="runbox">
                        <g:hiddenField name="project" value="${session.project}"/>

                        <g:render template="nodeFiltersHidden" model="${[params: params, query: query]}"/>

                        <div class=" col-sm-12">
                            <div class="input-group">
                                <g:textField name="exec" size="50" placeholder="Enter a shell command"
                                             value="${runCommand}"
                                             id="runFormExec"
                                             class="form-control"
                                             autofocus="true"/>

                                <span class="input-group-btn">
                                    <button class="btn btn-default has_tooltip" type="button"
                                            title="Node Dispatch Settings"
                                            data-placement="left"
                                            data-container="body"
                                            data-toggle="collapse" data-target="#runconfig">
                                        <i class="glyphicon glyphicon-cog"></i>
                                    </button>

                                    <button class="btn btn-success runbutton " onclick="runFormSubmit('runbox');">
                                        Run <span class="glyphicon glyphicon-play"></span>
                                    </button>
                                </span>
                            </div>

                        <div class="collapse well well-sm " id="runconfig">
                                <div class="row">
                                    <div class="col-sm-12">
                                        <div class="form-group text-muted ">Node Dispatch Settings:</div>

                                        <div class="form-group has_tooltip"
                                             title="Maximum number of parallel threads to use"
                                             data-placement="bottom">
                                            Thread count
                                        </div>

                                        <div class="form-group">
                                            <input min="1" type="number" name="nodeThreadcount" id="runNodeThreadcount"
                                                   size="2"
                                                   placeholder="Maximum threadcount for nodes" value="1"
                                                   class="form-control  input-sm"/>
                                        </div>

                                        <div class="form-group">On node failure:</div>

                                        <div class="radio">
                                            <label class="has_tooltip" title="Continue to execute on other nodes"
                                                   data-placement="bottom">
                                                <input type="radio" name="nodeKeepgoing"
                                                       value="true"
                                                       checked/> <strong>Continue</strong>
                                            </label>
                                        </div>

                                        <div class="radio">
                                            <label class="has_tooltip" title="Do not execute on any other nodes"
                                                   data-placement="bottom">
                                                <input type="radio" name="nodeKeepgoing"
                                                       value="false"/> <strong>Stop</strong>
                                            </label>
                                        </div>

                                        <div class="pull-right">
                                            <button class="close " data-toggle="collapse"
                                                    data-target="#runconfig">&times;</button>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="hiderun" id="runerror" style="display:none"></div>
                    </div>
                </g:if>
            </div>
        <div class="row row-space">
            <div class="col-sm-12">
%{--
                <g:link class="textbtn textbtn-default query"
                        title="Click to modify the filter"
                        action="nodes" controller="framework"
                        params="${query.filter?[filter:query.filter]:filterName?[filterName:filterName]:filterParams}">
                    <i class="glyphicon glyphicon-filter"></i>
                </g:link>--}%
                <a class="textbtn textbtn-default query act_showinlinenodefilter"
                        title="Click to modify the filter"
                        href="#nodeFilterInline"
                        data-toggle="collapse"
                        >
                    <i class="glyphicon glyphicon-filter"></i>
                </a>

                 <g:if test="${!emptyQuery}">
                    <g:if test="${total>5}">

                        <a class="h4 " data-toggle="collapse" href="#${ukey}nodeForm">
                            <span class="obs_nodes_allcount">${total}</span> Node<span
                                class="obs_nodes_allcount_plural">${1 != total ? 's' : ''}</span>
                            <b class="glyphicon glyphicon-chevron-right"></b>
                        </a>
                    </g:if>
                     <g:else>
                        <span class="obs_nodes_allcount">${total}</span> Node<span class="obs_nodes_allcount_plural">${1 != total ? 's' : ''}</span>
                     </g:else>
                </g:if>
                <span id="${ukey}nodeForm" class="${total>5?'collapse collapse-expandable':''}">
                    <g:render template="allnodes"
                              model="${[nodeview: 'embed', expanddetail: true, allnodes: allnodes, totalexecs: totalexecs, jobs: jobs, params: params, total: total, allcount: allcount, page: page, max: max, nodeauthrun: nodeauthrun, tagsummary: tagsummary]}"/>
                </span>
            </div>
            <div class="col-sm-12 form-horizontal collapse" id="nodeFilterInline">
                <div id="filterPresets">
                    presets...
                </div>
                <div>
                <g:render template="nodeFilterInputs"/>
                </div>
            </div>


        </div>



    <div id="runcontent" class="clearfix nodes_run_content" style="display: none"></div>

    <g:if test="${run_authorized}">
    <div class="row" id="activity_section">
    <div class="col-sm-12">
        <h4 class="text-muted"><g:message code="page.section.Activity.for.adhoc.commands" /></h4>
        <g:render template="/reports/activityLinks" model="[filter: [
                jobIdFilter: 'null',
                userFilter: session.user,
                projFilter: session.project
        ],
        knockoutBinding:true, showTitle:true]"/>
    </div>
    </div>
    </g:if>

</div>
<div id="loaderror"></div>
</body>
</html>