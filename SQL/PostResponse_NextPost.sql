CREATE procedure post.PostResponse_NextPost
	@UserID bigint, 					--current user ID
	@Direction varchar(10), 			--direction of swipe
	@Location varchar(10), 				--location in page (c or u)
	@PostPublicID varchar(100), 		--public ID of post
	@PartyPublicID varchar(250), 		--public ID of party		
	@SearchTerm varchar(250), 			--value to search by
	@HistNum int 						--number if historically viewing
--	@SortBy int 						--sort method
as 

set nocount on
--exec post.PostResponse_NextPostv3 743, 'down', 'o', '%%%-1896B520-A55D-40B9-B09D-03874E13EC5C', '0', '', 0

--write to log 
insert into log.NextPost select @UserID, @Direction, @Location, @PostPublicID, @PartyPublicID, @SearchTerm, @HistNum, getDate()
--select * from log.NextPost order by LogDate desc

declare @IsDirect bit = 0
if (charindex('%%%-',@PostPublicID) = 1)
	begin
		set @IsDirect = 1
		set @PostPublicID = right(@PostPublicID, len(@PostPublicID)-4)
		--insert into log.NextPost select @UserID, @Direction, @Location, @PostPublicID, @PartyPublicID, 'IsDirect' + convert(varchar(5),@IsDirect), @HistNum, getDate()
	end


declare @Data table (PostText varchar(1000), PostID bigint, PostPublicID varchar(250), PostAuthor varchar(250), PostAuthorHTML varchar(max), PostAuthorFollowStatus int, PostAuthorFollowStatusHTML varchar(max), PostTime varchar(50),
					PartyName varchar(250), PartyPublicKey varchar(250), IsPartyMember int, PartyMemberHTML varchar(max),
					IsFollowedPost int, IsFollowedPostHTML varchar(max), HistVal int, IsEndPost int, PostCommentCount int, Direction varchar(25), Location varchar(25),
					PctAffirm int, PctDeny int, ResponseDotHTML varchar(250))

declare		@ShowChart bit
select		@ShowChart = case 	when @Location in ('o','p') then 0							--fresh starts
								when @Location = 'c' and @Direction != 'down' then 0		--in center
								when @Location = 'u' and @Direction = 'up' then 0			--went back to center from up
								when @Location = 'c' and @Direction = 'down' then 1			--went to up
								when @Location = 'u' then 1									--still in up (and not back to center)
								else 0 end					

select		@HistNum = case 	when @ShowChart = 0 then 0
								--@ShowChart must be 1 for the following
								when @Direction = 'right' then @HistNum + 1
								when @Direction = 'left' and @HistNum > 1 then @HistNum - 1
								else 1 end						
								
								
								
					
--insert post response for latest swipe
if @Location in ('c','xc') and @Direction in ('left','right','up') and len(coalesce(@PostPublicID,'')) > 1 	--in correct location, swiping only L/R and known postID
	begin
		
		insert into post.PostResponse (PostID, PostResponseUserID, PostResponseValue, PostResponseCreateDate)	
		select		p.PostID,
					@UserID,
					case	when p.PostAuthorID = @UserID then -99	--shouldn't happen but noting anyway
							when @Direction = 'right' then 1		--affirm
							when @Direction = 'left' then -1 		--deny
							else 0 end as PostResponseValue,		--skip
					getDate()
		from		post.Post p
					left join person.Party py on p.PostPartyID = py.PartyID
					left join person.PartyPerson pys on py.PartyID = pys.PartyID and @UserID = pys.MemberID and 0 = pys.BannedInd
					left join post.PostResponse pr on p.PostID = pr.PostID and @UserID = pr.PostResponseUserID 
		where		p.PostPublicID = @PostPublicID
					and pr.PostID is null
					and 1 = case 	when py.PartyID is null then 1
									when py.PublicJoin = 1 then 1
									when pys.MemberID is not null then 1
									else 0 end
					and p.PostAuthorID != @UserID
	end

	
--get information for the next post to present	
;with PostCTE (PostText, PostID, PostPublicID, PostAuthor, PostAuthorID, PostAuthorFollowStatus, PostTime, PartyName, PartyPublicKey, IsPartyMember, IsFollowedPost, IsEndPost, PostResponseValue) as (
select		top 1 p.PostText,
			p.PostID,
			p.PostPublicID,
			ps.JUserName as PostAuthor,
			p.PostauthorID,
			coalesce(sf.PersonFollowStatusID,0) as PostAuthorFollowStatus,
			case 	when dateDiff(mi, p.PostCreateDate, getUTCDate()) < 1 then 'just now'
					when dateDiff(mi, p.PostCreateDate, getUTCDate()) < 61 then convert(varchar(10),dateDiff(mi, p.PostCreateDate, getUTCDate())) + 'm'
					when dateDiff(hh, p.PostCreateDate, getUTCDate()) < 25 then convert(varchar(10),dateDiff(hh, p.PostCreateDate, getUTCDate())) + 'h'
					else convert(varchar(10),dateDiff(dd, p.PostCreateDate, getUTCDate())) + 'd' end as PostTime,
			py.PartyName,
			case when len(coalesce(py.PartyPublicKey,'')) > 1 then py.PartyPublicKey else '0' end as PartyPublicKey,
			case when p.PostPartyID = 0 then 0 else coalesce(pys.PartyPersonStatusID,0) end as IsPartyMember,
			case when pf.PostID is not null then 1 else 0 end as IsFollowedPost,
			coalesce(hh.IsEndPost,0) as IsEndPost,
			case when p.PostAuthorID = @UserID then p.PostPosition else pr.PostResponseValue end as PostResponseValue
from		post.vPost p
			inner join person.Person ps on p.PostAuthorID = ps.JUserID
			left join person.PersonFollow sf on p.PostAuthorID = sf.FollowedUserID and @UserID = sf.FollowerUserID
			left join post.PostFollow pf on p.PostID = pf.PostID and @UserID = pf.FollowUserID and 1 = ActiveInd
			left join post.PostResponse pr on p.postID = pr.postID and @UserID = pr.PostResponseUserID  
			left join person.Party py on p.PostPartyID = py.PartyID
			left join person.PartyPerson pys on py.PartyID = pys.PartyID and @UserID = pys.MemberID
			--needed for history (u/chart area)
			left join 	(
						select		PostID, case when coalesce(RNX,1) = 1 then 1 else 0 end as IsEndPost
						from		(
									select 		xpr.PostID, 
									row_number() over (order by xpr.PostResponseCreateDate desc) RN,
									row_number() over (order by xpr.PostResponseCreateDate) RNX
									from 		post.PostResponse xpr
												inner join post.Post xxp on xpr.PostID = xxp.PostID
									where 		coalesce(xxp.PostParentID,0) = 0
												and xpr.PostResponseUserID = @UserID
									) h
						where		RN = @HistNum
						) hh on p.postID = hh.PostID
		
where		1=1
			--general party rules
			and 1 = case	when coalesce(p.PostPartyID,0) = 0 then 1 													--BIQR general > allow
							when py.publicJoin = 1 then 1																--Public allowed to see (and respond) to this party
							when pys.PartyPersonID is not null and pys.BannedInd = 0 then 1								--Person is member to this party
							else 0 end

			and 1 = case	when @IsDirect = 1 and @PostPublicID = p.PostPublicID then 1
							when @IsDirect != 1
								and p.PostAuthorID != @UserID																				--don't show posts for given user
								and coalesce(sf.PersonFollowStatusID,0) >= 0																--don't include blocked members
								and coalesce(pys.PartyPersonStatusID,0) >= 0																--don't include ignored / banned parties
								--specific party logic			
								and 1 = case 	when len(coalesce(@PartyPublicID,'0')) <= 1 then 1											--no party provided
												when len(coalesce(@PartyPublicID,'0')) > 1 and @PartyPublicID = py.PartyPublicKey then 1	--party provided, limit to this
												else 0 end
								--specific search term logic
								and 1 = case	when len(coalesce(rtrim(@SearchTerm),'')) < 1 then 1										--no search term
												when p.PostText like '%'+@SearchTerm+'%' then 1												--look for certain data
												else 0 end
								--history/chart logic
								and 1 = case	when @ShowChart = 0 and pr.PostResponseID is null then 1									--ignore history and MUST not be answered
												when @ShowChart = 1 and hh.PostID is not null then 1										--only specific historical post
												else 0 end
												
							then 1
							else 0 end
			
order by	case when coalesce(pys.PartyPersonStatusID,0) = 9 then 1 else 99 end,										--move favorite parties to top
			case when coalesce(sf.PersonFollowStatusID,0) = 1 then 1 else 99 end,										--move followed users to next top
			p.PostCreateDate desc							
)						
	


--get selected post with supporting information and transformations
insert into @Data
select 		x.PostText,
			x.PostID,
			x.PostPublicID,
			x.PostAuthor,
			'<i class=''far '+coalesce(av.AvatarCode,'fa-meh')+' icon-avatar''></i>' + x.PostAuthor + ' : ' + x.PostTime as PostAuthorHTML,	--eventually make avatar dynamic
			x.PostAuthorFollowStatus,
			case x.PostAuthorFollowStatus	when 1 then '<i class=''fas fa-chevron-circle-up icon-a''></i>' --follow person
											when -1 then '<i class=''fas fa-times-circle icon-d''></i>' --foe person
											else '<i class=''fas fa-chevron-circle-up icon-grey''></i>' end as PostAuthorFollowStatusHTML,
			x.PostTime,
			x.PartyName,
			x.PartyPublicKey,
			x.IsPartyMember,
			case x.IsPartyMember	when 1 then '<i class=''fas fa-plus-circle icon-a''></i>'	--follow party
									when 9 then	'<i class=''fas fa-chevron-circle-up icon-a''></i>'	--fav party
									when -1 then '<i class=''fas fa-times-circle icon-d''></i>' --foe party
									else '<i class=''fas fa-plus-circle icon-grey''></i>' end as PartyMemberHTML,			
			x.IsFollowedPost,
			case when x.IsFollowedPost = 1 then '<i class=''fas fa-heart icon-d''></i>' else '<i class=''fas fa-heart''></i>' end isFollowedPostHTML,
			@HistNum as HistVal,			
			x.IsEndPost,
			coalesce(ct.PostCommentCount,0) as PostCommentCount,
			@Direction as Direction,
			case	when @IsDirect = 1 and x.PostAuthorID = @UserID then 'xu'
					when @IsDirect = 1 and x.PostResponseValue is not null then 'xu'
					when @IsDirect = 1 and x.PostResponseValue is null then 'xc'
					else @Location end as Location,
			coalesce(uuu.PctAffirm,0) as PctAffirm,
			coalesce(100 - uuu.PctAffirm,0) as PctDeny,
			case 	when x.PostResponseValue = -1 then '<i style=''color:#F6511D'' class=''fas fa-circle''></i>'
					when x.PostResponseValue = 1 then '<i style=''color:#00A6ED'' class=''fas fa-circle''></i>'
					when x.PostResponseValue = 0 then '<i style=''color:#C8C8C8'' class=''fas fa-circle''></i>'
					else '' end as ResponseDotHTML
from		PostCTE x
			left join	(--get avatar
						select		avp.JUserID as UserID,
									avp.AvatarCode
						from		person.Person avp
									inner join PostCTE acte on avp.JUserID = acte.PostAuthorID
						) av on x.PostAuthorID = av.UserID
			left join	(--get comment counts
						select		xcte.PostID,
									count(ctp.PostID) as PostCommentCount
						from		post.Post ctp
									inner join PostCTE xcte on ctp.PostParentID = xcte.PostID
						--where		ctp.PostAuthorID != @UserID
						group by	xcte.PostID
						) ct on x.PostID = ct.PostID
			left join	(--get chart data
						select		PostID,
									Round((CountAffirm*1.0) / (CountTotal*1.0) * 100, 0) as PctAffirm
						from		(			
									select		PostID,
												count(*) as CountTotal,
												sum(case when u.PostResponseValue = 1 then 1 else 0 end) as CountAffirm
									from		(			
									
												select		pr.postID, pr.PostResponseValue
												from		post.PostResponse pr
															inner join PostCTE x on pr.PostID = x.PostID
												where		pr.PostResponseValue in (-1,1)
												
												union all 	
												
												select		p.postID,
															p.PostPosition
												from		post.Post p
															inner join PostCTE x on p.PostID = x.PostID
												) u
									group by	PostID			
									) uu
						) uuu on x.PostID = uuu.PostID

if not exists (select * from @Data)
	begin
		
		insert into @Data
		select		'<div style=''padding-top:150px''>No available posts at this time.  Please try again later</div>' as PostText,
					0 as PostID,
					'0' as PostPublicID, 
					'' as PostAuthor,
					'' as PostAuthorHTML,
					0 as PostAuthorFollowStatus,
					'' as PostAuthorFollowStatusHTML,
					'' as PostTime, 
					'' as PartyName,
					'' as PartyPublicKey,
					0 as IsPartyMember,
					'' as PartyMemberHTML,
					0 as IsFollowedPost,
					'' as IsFollowedPostHTML, 
					0 as HistVal,
					0 as IsEndPost,
					0 as PostCommentCount,
					'X' as Direction,
					'X' as Location,
					0 as PctAffirm, 
					0 as PctDeny,
					'' as ResponseDotHTML
	
	end
						
select * from @Data;
