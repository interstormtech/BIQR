alter procedure post.PostResponse_NextComment
	@UserID bigint,
	@PostPublicID varchar(250),
	@CommentPublicID varchar(250),
	@Direction varchar(10),
	@CommentType int,	--1 = swipe, 2 = review
	@Page int,
	@SortType int		--0= credibility, 1 = followed authors, 2 = newest, 3 = oldest
as

set nocount on

insert into log.NextComment (UserID, PostPublicID, CommentPublicID, Direction, CommentType, Page, SortType)
select		@UserID, @PostPublicID, @CommentPublicID, @Direction, @CommentType, @Page, @SortType

/*
declare		@userID bigint = 139
declare		@PostPublicID varchar(250) = 'D668B80B-B959-4FEC-B1CA-7A74D8359598'
*/

declare		@Data table (PostText varchar(1000), PostAuthor varchar(250), PostAuthorFollowStatus int, PostAuthorFollowStatusHTML varchar(max), PostTime varchar(50), 
					CommentPublicID varchar(250), CommentText varchar(1000), CommentAuthor varchar(250), CommentAuthorHTML varchar(max), CommentAuthorFollowStatus int, CommentAuthorFollowStatusHTML varchar(max), CommentTime varchar(50),
					RN int, Page int, PostCommentCount int)
	
if @Page = 0
	set @Page = 1
else
	begin
		if @Direction = 'left'
			set @Page = @Page + 1
		if @Direction = 'right'
			if @Page > 1
				set @Page = @Page - 1
	end
					
					
--insert comment response for latest swipe
if @CommentType = 1 and @Direction in ('left','right','up') and len(coalesce(@CommentPublicID,'')) > 1 	--swipe L/R/U & known postPublicID (commentPublicID)
	begin
		
		insert into post.PostResponse (PostID, PostResponseUserID, PostResponseValue, PostResponseCreateDate)	
		select		c.PostID,
					@UserID,
					case	when p.PostAuthorID = @UserID then -99	--shouldn't happen but noting anyway
							when @Direction = 'right' then 1		--affirm
							when @Direction = 'left' then -1 		--deny
							else 0 end as PostResponseValue,		--skip
					getDate()
		from		post.Post p
					inner join post.Post c on p.PostID = c.PostParentID
					left join person.Party py on p.PostPartyID = py.PartyID
					left join person.PartyPerson pys on py.PartyID = pys.PartyID and @UserID = pys.MemberID and 0 = pys.BannedInd
					left join post.PostResponse pr on c.PostID = pr.PostID and @UserID = pr.PostResponseUserID 
		where		c.PostPublicID = @CommentPublicID
					and pr.PostID is null
					and 1 = case 	when py.PartyID is null then 1
									when py.PublicJoin = 1 then 1
									when pys.MemberID is not null then 1
									else 0 end
					and c.PostAuthorID != @UserID
	end
					
					
					
;with CTE (PostText, PostAuthor, PostAuthorFollowStatus, PostAuthorFollowStatusHTML, PostTime, CommentPublicID, CommentText, CommentAuthor, CommentAuthorHTML, 
			CommentAuthorFollowStatus, CommentAuthorFollowStatusHTML, CommentTime, RN) as (					
select		p.PostText,
			pp.JUserName as PostAuthor,
			coalesce(pf.PersonFollowStatusID,0) as PostAuthorFollowStatus,
			case coalesce(pf.PersonFollowStatusID,0)	when 1 then '<i class=''fas fa-chevron-circle-up icon-a''></i>' --follow person
														when -1 then '<i class=''fas fa-times-circle icon-d''></i>' --foe person
														else '<i class=''fas fa-chevron-circle-up icon-grey''></i>' end as PostAuthorFollowStatusHTML,				
			case 	when dateDiff(mi, p.PostCreateDate, getUTCDate()) < 1 then 'just now'
					when dateDiff(mi, p.PostCreateDate, getUTCDate()) < 61 then convert(varchar(10),dateDiff(mi, p.PostCreateDate, getUTCDate())) + 'm'
					when dateDiff(hh, p.PostCreateDate, getUTCDate()) < 25 then convert(varchar(10),dateDiff(hh, p.PostCreateDate, getUTCDate())) + 'h'
					else convert(varchar(10),dateDiff(dd, p.PostCreateDate, getUTCDate())) + 'd' end as PostTime,
			c.PostPublicID as CommentPublicID,
			
			case 	when @CommentType != 2 then ''
					when @CommentType = 2 and r.PostResponseValue = -1 then '<i style=''color:#F6511D'' class=''fas fa-circle''></i> '
					when @CommentType = 2 and c.PostAuthorID = @UserID and c.PostPosition = -1 then '<i style=''color:#F6511D'' class=''fas fa-circle''></i> '
					when @CommentType = 2 and r.PostResponseValue = 1 then '<i style=''color:#00A6ED''class=''fas fa-circle''></i> '
					when @CommentType = 2 and c.PostAuthorID = @UserID and c.PostPosition = 1 then '<i style=''color:#00A6ED''class=''fas fa-circle''></i> '
					when @CommentType = 2 then '<i style=''color:#C8C8C8''class=''fas fa-circle''></i> ' 
					else '' end +
			c.PostText as CommentText,
			cp.JUserName as CommentAuthor,
			'<i class=''far fa-angry icon-avatar''></i>' + cp.JUserName + ' : ' +
				case 	when dateDiff(mi, c.PostCreateDate, getUTCDate()) < 1 then 'just now'
						when dateDiff(mi, c.PostCreateDate, getUTCDate()) < 61 then convert(varchar(10),dateDiff(mi, c.PostCreateDate, getUTCDate())) + 'm'
						when dateDiff(hh, c.PostCreateDate, getUTCDate()) < 25 then convert(varchar(10),dateDiff(hh, c.PostCreateDate, getUTCDate())) + 'h'
						else convert(varchar(10),dateDiff(dd, c.PostCreateDate, getUTCDate())) + 'd' end as CommentAuthorHTML,
			coalesce(cf.PersonFollowStatusID,0) as CommentAuthorFollowStatus,
			case coalesce(cf.PersonFollowStatusID,0)	when 1 then '<i class=''fas fa-chevron-circle-up icon-a''></i>' --follow person
														when -1 then '<i class=''fas fa-times-circle icon-d''></i>' --foe person
														else '<i class=''fas fa-chevron-circle-up icon-grey''></i>' end as CommentAuthorFollowStatusHTML,			
			case 	when dateDiff(mi, c.PostCreateDate, getUTCDate()) < 1 then 'just now'
					when dateDiff(mi, c.PostCreateDate, getUTCDate()) < 61 then convert(varchar(10),dateDiff(mi, c.PostCreateDate, getUTCDate())) + 'm'
					when dateDiff(hh, c.PostCreateDate, getUTCDate()) < 25 then convert(varchar(10),dateDiff(hh, c.PostCreateDate, getUTCDate())) + 'h'
					else convert(varchar(10),dateDiff(dd, c.PostCreateDate, getUTCDate())) + 'd' end as CommentTime,
			row_number() over (order by	
				case 	when @SortType = 0 then py.CredibilityRank * -1 --doing this to make best rank a "higher" number
						when @SortType = 1 then cf.PersonFollowStatusID
						when @SortType = 2 then c.PostCreateDate
						when @SortType = 3 then dateDiff(ss, c.PostCreateDate, getUTCDate())
						else 0 end desc,
				case when c.PostAuthorID = @UserID then c.PostCreateDate else r.PostResponseCreateDate end desc, 
				coalesce(cf.PersonFollowStatusID,0) desc, 
				c.PostCreateDate desc
				) as RN					
from		post.Post p
			inner join person.Person pp on p.PostAuthorID = pp.JUserID
			left join person.PersonFollow pf on p.PostAuthorID = pf.FollowerUserID and @UserID = pf.FollowerUserID			
			left join post.Post c on p.PostID = c.PostParentID 
			left join person.Person cp on c.PostAuthorID = cp.JUserID
			left join person.PersonFollow cf on c.PostAuthorID = cf.FollowerUserID and @UserID = cf.FollowerUserID
			left join post.PostResponse r on c.PostID = r.PostID and @UserID = r.PostResponseUserID
			left join person.PartyPerson py on c.PostAuthorID = py.MemberID and c.PostPartyID = py.PartyID
where		p.PostPublicID = @PostPublicID
			and 1 = case 	when @CommentType = 1 and c.PostAuthorID != @UserID and r.PostResponseID is null and coalesce(cf.PersonFollowStatusID,0) >= 0 then 1
							when @CommentType = 2 and r.PostResponseID is not null then 1 
							when @CommentType = 2 and c.PostAuthorID = @UserID then 1
							else 0 end
)


insert into @Data
select		top 1 *, @Page as Page, (select count(*) from CTE) as PostCommentCount
from		CTE
where		RN = coalesce(@Page,1)


if not exists (select * from @Data)
	begin
		if @Page > 1
			set @Page = @Page - 1
		
		insert into @Data
		select		p.PostText,
					pp.JUserName as PostAuthor,
					coalesce(pf.PersonFollowStatusID,0) as PostAuthorFollowStatus,
					case coalesce(pf.PersonFollowStatusID,0)	when 1 then '<i class=''fas fa-chevron-circle-up icon-a''></i>' --follow person
																when -1 then '<i class=''fas fa-times-circle icon-d''></i>' --foe person
																else '<i class=''fas fa-chevron-circle-up icon-grey''></i>' end as PostAuthorFollowStatusHTML,				
					case 	when dateDiff(mi, p.PostCreateDate, getUTCDate()) < 1 then 'just now'
							when dateDiff(mi, p.PostCreateDate, getUTCDate()) < 61 then convert(varchar(10),dateDiff(mi, p.PostCreateDate, getUTCDate())) + 'm'
							when dateDiff(hh, p.PostCreateDate, getUTCDate()) < 25 then convert(varchar(10),dateDiff(hh, p.PostCreateDate, getUTCDate())) + 'h'
							else convert(varchar(10),dateDiff(dd, p.PostCreateDate, getUTCDate())) + 'd' end as PostTime,
					'0' as CommentPublicID,
					case 	when @CommentType = 2 then 'End of comments you have rated, please review more comments' 
							else 'No available comments.  Please check back later' end as CommentText,
					'' as CommentAuthor,
					'' as CommentAuthorHTML,
					0 as CommentAuthorFollowStatus,
					'' as CommentAuthorFollowStatusHTML,			
					'' as CommentTime,
					@Page as RN,
					@Page as Page,
					0
		from		post.Post p
					inner join person.Person pp on p.PostAuthorID = pp.JUserID
					left join person.PersonFollow pf on p.PostAuthorID = pf.FollowerUserID and @UserID = pf.FollowerUserID			
		where		p.PostPublicID = @PostPublicID
		
	end 
			
select * from @Data;
