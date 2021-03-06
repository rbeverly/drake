classdef RigidBody < RigidBodyElement
  
  properties 
    robotnum = 0;  % this body is associated with a particular robot/object number, named in model.name{objnum} 
    
    % link properties
    linkname='';  % name of the associated link
    % NOTE: dofnum is deprecated, use position_num or velocity_num instead
    position_num=0;     % the indices into the joint configuration (q) vector corresponding to this joint
    velocity_num=0;     % the indices into the joint velocity (v) vector corresponding to this joint
    gravity_off=false;
    
    visual_shapes={}; % objects of type RigidBodyGeometry
    contact_shapes={}; % objects of type RigidBodyGeometry

    contact_shape_group_name={};  % string names of the groups
    contact_shape_group={}; % contact_shape_group{i} is a list of indices into contact_shapes which belong to contact_shape_group_name{i}
    
    % joint properties
    parent=0;       % index (starting at 1) for rigid body parent.  0 means no parent
    jointname='';
    pitch=0;        % for featherstone 3D models
    floating=0; % 0 = not floating base, 1 = rpy floating base, 2 = quaternion floating base
    joint_axis=[1;0;0]; 
    Xtree=eye(6);   % velocity space coordinate transform *from parent to this node*
    X_joint_to_body=eye(6);  % velocity space coordinate transfrom from joint frame (where joint_axis = z-axis) to body frame 
    Ttree=eye(4);   % position space coordinate transform *from this node to parent*
    T_body_to_joint=eye(4);
    wrljoint='';  % tranformation to joint coordinates in wrl syntax
    damping=0; % viscous friction term
    coulomb_friction=0; 
    static_friction=0; % currently not used for simulation
    coulomb_window=eps; % the threshold around zero velocity used for the PWL friction model (See Khalil and Dombre, Fig. 9.2(d))
    joint_limit_min=[];
    joint_limit_max=[];
    effort_min=[];
    effort_max=[];
    velocity_limit=[];
    has_position_sensor=false;
  end
  
  properties (SetAccess=protected, GetAccess=public)    
    % mass, com, inertia properties
    I=zeros(6);  % total spatial mass matrix, sum of mass, inertia, (and added mass for submerged bodies)
    Imass=zeros(6);  % spatial mass/inertia
    Iaddedmass = zeros(6); % added mass spatial matrix
    mass = 0;
    com = [];
    inertia = [];

    % Collision filter properties
    collision_filter = struct('belongs_to',CollisionFilterGroup.DEFAULT_COLLISION_FILTER_GROUP_ID, ...
                             'collides_with',CollisionFilterGroup.ALL_COLLISION_FILTER_GROUPS);
  end
  
  methods    
    function contact_pts(body)
      error('contact_pts has been replaced by contact_shapes');
    end
    
    function varargout = forwardKin(varargin)
      error('forwardKin(body,...) has been replaced by forwardKin(model,body_num,...), because it has a mex version.  please update your kinematics calls');
    end

    function pts = getTerrainContactPoints(body,collision_group)
      % pts = getTerrainContactPoints(body) returns the terrain contact
      % points of all geometries on this body, in body frame.
      %
      % pts = getTerrainContactPoints(body,collision_group) returns the
      % terrain contact points of all geometries on this body belonging
      % to the group[s] specified by collision_group
      %
      % For a general description of terrain contact points see 
      % <a href="matlab:help RigidBodyGeometry/getTerrainContactPoints">RigidBodyGeometry/getTerrainContactPoints</a>
      %
      % @param body - A RigidBody object
      % @param collision_group - A string or cell array of strings
      %                          specifying the collision groups whose
      %                          terrain contact points should be
      %                          returned
      % @retval pts - A 3xm array of points on body (in body frame) that can collide with
      %               non-flat terrain
      if nargin < 2
        pts = cell2mat(cellfun(@(shape) shape.getTerrainContactPoints(), ...
                               body.contact_shapes, ...
                               'UniformOutput',false));
      else
        typecheck(collision_group,{'char','cell'});
        pts = cell2mat(cellfun(@(shape) shape.getTerrainContactPoints(), ...
          body.getContactShapes(collision_group), ...
          'UniformOutput',false));
      end
    end
    
    function [pts,inds] = getContactPoints(body,collision_group)
      error('contact points have been replaced by contact shapes');
    end

    function dofnum(obj)
      error('the dofnum parameter is no longer supported, use position_num and velocity_num instead');
    end
    
    function shapes = getContactShapes(body,collision_group,collision_ind)
      % @param collision_group (optional) return structures for only the
      % contact_shapes in that group.  can be an integer index or a string.
      if (nargin<2) 
        shapes = body.contact_shapes;
      else
        if ~isnumeric(collision_group)
          typecheck(collision_group,{'char','cell'});
          collision_group = find(ismember(body.contact_shape_group_name,collision_group));
        end
        if (nargin < 3)
          shapes = body.contact_shapes([body.contact_shape_group{collision_group}]);
        else
          shapes = body.contact_shapes(body.contact_shape_group{collision_group}(collision_ind));
        end
      end
    end

    function [body,body_changed] = replaceCylindersWithCapsules(body)
      % [body,body_changed] = replaceCylindersWithCapsules(body) returns
      % the body with all RigidBodyCylinders in contact_shapes replaced
      % by RigidBodyCapsules of the same dimensions.
      %
      % @param body - RigidBody object
      %
      % @retval body - RigidBody object
      % @retval body_changed - Logical indicating whether any
      %                        replacements were made.
      %
      cylinder_idx = cellfun(@(shape) isa(shape,'RigidBodyCylinder'), ...
                             body.contact_shapes);
      if ~any(cylinder_idx)
        body_changed = false;
      else
        body.contact_shapes(cylinder_idx) = ...
          cellfun(@(shape) shape.toCapsule(), ...
                  body.contact_shapes(cylinder_idx), ...
                  'UniformOutput',false);
        body_changed = true;
      end
    end
     
    function body = replaceContactShapesWithCHull(body,scale_factor)
      pts = [];
      for i = 1:length(body.contact_shapes)
        pts = [pts, body.contact_shapes{i}.getPoints()];
      end
      if ~isempty(pts)
        pts =pts(:,unique(convhull(pts')));
        if nargin > 1
          mean_of_pts = mean(pts,2);
          pts = bsxfun(@plus,scale_factor*bsxfun(@minus,pts,mean_of_pts),mean_of_pts);
        end
        body.contact_shapes = {};
        body.contact_shape_group = {};
        body.contact_shape_group_name = {};
        body = body.addContactShape(RigidBodyMeshPoints(pts));
      end
    end
    
    function body = removeCollisionGroups(body,contact_groups)
      if isempty(body.contact_shapes), 
        return; 
      end % nothing to do for this body
      if ~iscell(contact_groups), 
        contact_groups={contact_groups}; 
      end
      for i=1:length(contact_groups)
        % boolean identifying if this contact_shape_group is being removed
        group_elements = strcmpi(contact_groups{i},body.contact_shape_group_name);
        if ~isempty(group_elements)
          % indices of the body.contact_shapes that are being removed
          contact_inds = [body.contact_shape_group{group_elements}];
          
          if ~isempty(contact_inds)
            % indices of contact shapes that are *not* being removed
            keep_inds = setdiff(1:length(body.contact_shapes),contact_inds);
            
            % for each contact_shape_group, need to re-assign contact shape
            % indices, since some are being removed
            ripts = nan(1,length(body.contact_shapes));  % reverse index
            ripts(keep_inds) = 1:length(keep_inds);
            for j=1:length(body.contact_shape_group)
              body.contact_shape_group{j}=ripts(body.contact_shape_group{j});
            end
            % remove contact shapes
            body.contact_shapes(:,contact_inds) = [];
          end
          % remove contact_shape_groups and names
          body.contact_shape_group(group_elements) = [];          
          body.contact_shape_group_name(group_elements) = [];
        end
      end
    end
        
    function body = removeCollisionGroupsExcept(body,contact_groups)
      if isempty(body.contact_shapes), 
        return; 
      end % nothing to do for this body
      if ~iscell(contact_groups), 
        contact_groups={contact_groups}; 
      end
      i=1;
      while i<=length(body.contact_shape_group)
        %check of body.contact_shape_group_name should not be kept
        if ~ismember(body.contact_shape_group_name{i},contact_groups)
          % indices of the body.contact_shapes that are being removed
          contact_inds = [body.contact_shape_group{i}];
          
          if ~isempty(contact_inds)
            % indices of contact shapes that are *not* being removed
            keep_inds = setdiff(1:length(body.contact_shapes),contact_inds);
            
            % for each contact_shape_group, need to re-assign contact shape
            % indices, since some are being removed
            ripts = nan(1,length(body.contact_shapes));  % reverse index
            ripts(keep_inds) = 1:length(keep_inds);
            for j=1:length(body.contact_shape_group)
              body.contact_shape_group{j}=ripts(body.contact_shape_group{j});
            end
            % remove contact shapes
            body.contact_shapes(:,contact_inds) = [];
          end
          % remove contact_shape_groups and names
          body.contact_shape_group(i) = [];          
          body.contact_shape_group_name(i) = [];
        else
          i=i+1;
        end
      end
    end

    function body = makeBelongToNoCollisionFilterGroups(body)
      body.collision_filter.belongs_to = CollisionFilterGroup.NO_COLLISION_FILTER_GROUPS;
    end
    
    function body = makeIgnoreNoCollisionFilterGroups(body)
      body.collision_filter.collides_with = CollisionFilterGroup.ALL_COLLISION_FILTER_GROUPS;
    end

    function body = makeBelongToCollisionFilterGroup(body,collision_fg_id)
      for id = reshape(collision_fg_id,1,[])
        body.collision_filter.belongs_to = ...
          bitor(body.collision_filter.belongs_to,bitshift(1,id-1));
      end
    end

    function body = makeIgnoreCollisionFilterGroup(body,collision_fg_id)
      for id = reshape(collision_fg_id,1,[])
        body.collision_filter.collides_with = ...
          bitand(body.collision_filter.collides_with,bitcmp(bitshift(uint16(1),id-1)));
      end
    end

    function newbody = copy(body)
      % makes a shallow copy of the body
      % note that this functionality is in matlab.mixin.Copyable in newer
      % versions of matlab, but I've done it myself since i want to support
      % < v2011
      
      newbody=RigidBody();
      p=properties(body);
      for i=1:length(p)
        eval(['newbody.',p{i},'=body.',p{i}]);
      end
    end
    
    % Note: bindParams and updateParams are copies of the methods in 
    % RigidBodyElement (yuck!) because the RigidBodyElement version does 
    % not have permissions to do the reflection on the protected properties 
    % in this class.
    function body=bindParams(body,model,pval)
      fr = getParamFrame(model);
      pn = properties(body);
      for i=1:length(pn)
        if isa(body.(pn{i}),'msspoly')
          body.param_bindings.(pn{i}) = body.(pn{i});
          body.(pn{i}) = double(subs(body.(pn{i}),fr.getPoly,pval));
        end
      end
    end
    
    function body=updateParams(body,poly,pval)
      % this is only intended to be called from the parent manipulator
      % class. (maybe I should move it up to there?)
      fn = fieldnames(body.param_bindings);
      for i=1:length(fn)
        body.(fn{i}) = double(subs(body.param_bindings.(fn{i}),poly,pval));
      end
    end
    
    function body=parseInertial(body,node,model,options)
      mass = 0;
      inertia = zeros(3);
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(parseParamString(model,body.robotnum,char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(parseParamString(model,body.robotnum,char(origin.getAttribute('rpy'))),3,1);
        end
      end
      massnode = node.getElementsByTagName('mass').item(0);
      if ~isempty(massnode)
        if (massnode.hasAttribute('value'))
          mass = parseParamString(model,body.robotnum,char(massnode.getAttribute('value')));
        end
      end
      inode = node.getElementsByTagName('inertia').item(0);
      if ~isempty(inode)
        if inode.hasAttribute('ixx'), ixx = parseParamString(model,body.robotnum,char(inode.getAttribute('ixx'))); else ixx=0; end
        if inode.hasAttribute('ixy'), ixy = parseParamString(model,body.robotnum,char(inode.getAttribute('ixy'))); else ixy=0; end
        if inode.hasAttribute('ixz'), ixz = parseParamString(model,body.robotnum,char(inode.getAttribute('ixz'))); else ixz=0; end
        if inode.hasAttribute('iyy'), iyy = parseParamString(model,body.robotnum,char(inode.getAttribute('iyy'))); else iyy=0; end
        if inode.hasAttribute('iyz'), iyz = parseParamString(model,body.robotnum,char(inode.getAttribute('iyz'))); else iyz=0; end
        if inode.hasAttribute('izz'), izz = parseParamString(model,body.robotnum,char(inode.getAttribute('izz'))); else izz=0; end
        inertia = [ixx, ixy, ixz; ixy, iyy, iyz; ixz, iyz, izz];
      end
      
      % randomly scale inertia
      % keep scale factor positive to ensure positive definiteness
      % x'*I*x > 0 && eta > 0 ==> x'*(eta*I)*x > 0
      eta = 1 + min(1,max(-0.9999,options.inertia_error*randn()));
      inertia = eta*inertia;  
      
      if any(rpy)
        error([body.linkname,': rpy in inertia block not implemented yet (but would be easy)']);
      end
      body = setInertial(body,mass,xyz,inertia);
    end
    
    function body = setInertial(body,varargin)
      % setInertial(body,mass,com,inertia [,addedmass]) or setInertial(body,spatialI [,addedmass])
      % this guards against things getting out of sync
      % Updated 4/5/2014 to allow for added mass effects (for submerged bodies)
      
      function v = skew(A)
        v = 0.5 * [ A(3,2) - A(2,3);
          A(1,3) - A(3,1);
          A(2,1) - A(1,2) ];
      end
      
      if nargin==2 || nargin==3
        sizecheck(varargin{1},[6 6]);
        % extract mass, center of mass, and inertia information from the
        % spatial I matrix
        body.Imass = varargin{1};
        body.mass = body.Imass(6,6);
        mC = body.Imass(1:3,4:6);
        body.com = skew(mC)/body.mass;
        body.inertia = body.Imass(1:3,1:3) - mC*mC'/body.mass;
        if nargin==3
            % Set added mass matrix
            sizecheck(varargin{2},[6 6]);
            body.Iaddedmass = varargin{2};
        end
        
      elseif nargin==4 || nargin==5
          % Set mass, center of mass, and inertia directly
        sizecheck(varargin{1},1);
        sizecheck(varargin{2},[3 1]);
        sizecheck(varargin{3},[3 3]);
        body.mass = varargin{1};
        body.com = varargin{2};
        body.inertia = varargin{3};
        body.Imass = mcI(body.mass,body.com,body.inertia);
        if nargin==5
            % Set added mass matrix
            sizecheck(varargin{4},[6 6]);
            body.Iaddedmass = varargin{4};
        end
        
      else
        error('wrong number of arguments');
      end
      body.I = body.Imass+body.Iaddedmass;
      
      if isnumeric(body.I) && ~valuecheck(body.I'-body.I,zeros(6)); %Check symmetry of matrix
          warning('Spatial mass matrix is not symmetric, this is non-physical');
      end
    end    
    
    function body = parseVisual(body,node,model,options)
      c = .7*[1 1 1];
      
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(parseParamString(model,body.robotnum,char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(parseParamString(model,body.robotnum,char(origin.getAttribute('rpy'))),3,1);
        end
      end
        
      matnode = node.getElementsByTagName('material').item(0);
      if ~isempty(matnode)
        c = RigidBodyManipulator.parseMaterial(matnode,options);
      end
      
      geomnode = node.getElementsByTagName('geometry').item(0);
      if ~isempty(geomnode)
        if (options.visual || options.visual_geometry)
          shape = RigidBodyGeometry.parseURDFNode(geomnode,xyz,rpy,model,body.robotnum,options);
          shape.c = c;
          body.visual_shapes = {body.visual_shapes{:},shape};
        end
      end        
    end
    
    function body = parseCollision(body,node,model,options)
      xyz=zeros(3,1); rpy=zeros(3,1);
      origin = node.getElementsByTagName('origin').item(0);  % seems to be ok, even if origin tag doesn't exist
      if ~isempty(origin)
        if origin.hasAttribute('xyz')
          xyz = reshape(parseParamString(model,body.robotnum,char(origin.getAttribute('xyz'))),3,1);
        end
        if origin.hasAttribute('rpy')
          rpy = reshape(parseParamString(model,body.robotnum,char(origin.getAttribute('rpy'))),3,1);
        end
      end
      
      geomnode = node.getElementsByTagName('geometry').item(0);
      if ~isempty(geomnode)
        shape = RigidBodyGeometry.parseURDFNode(geomnode,xyz,rpy,model,body.robotnum,options);
        if (node.hasAttribute('group'))
          name=char(node.getAttribute('group'));
        else
          name='default';
        end
        body = addContactShape(body,shape,name);
      end
    end

    function body = addContactShape(body,shape,name)
      if nargin < 3, name='default'; end
      shape.name = name;
      body.contact_shapes = [body.contact_shapes,{shape}];
      ind = find(strcmp(body.contact_shape_group_name,name));
      if isempty(ind)
        body.contact_shape_group_name=horzcat(body.contact_shape_group_name,name);
        ind=length(body.contact_shape_group_name);
        body.contact_shape_group{ind} = length(body.contact_shapes);
      else
        body.contact_shape_group{ind} = [body.contact_shape_group{ind},length(body.contact_shapes)];
      end
    end
  end
  
  methods (Static)
    function testRemoveCollisionGroups
      body = RigidBody();
      shape1 = RigidBodySphere(1);
      shape2 = RigidBodySphere(2);
      shape3 = RigidBodySphere(3);
      shape4 = RigidBodySphere(3);
      shape5 = RigidBodySphere(3);
      body.contact_shapes = {shape1, shape2, shape3, shape4, shape5};
      body.contact_shape_group_name = {'group1','group2','group3'};
      body.contact_shape_group = {[1 4],2,[3 5]};
      body2 = body.removeCollisionGroups('group1');
      body3 = body.removeCollisionGroups('group2');
      body4 = body.removeCollisionGroups('group2adfs');
      
      assert(isequal(body2.contact_shapes,{shape2, shape3, shape5}));
      assert(isequal(body2.contact_shape_group_name,{'group2','group3'}));
      assert(isequal(body2.contact_shape_group,{[1], [2 3]}));
      
      assert(isequal(body3.contact_shapes,{shape1, shape3, shape4, shape5}));
      assert(isequal(body3.contact_shape_group_name,{'group1','group3'}));
      assert(isequal(body3.contact_shape_group,{[1 3], [2 4]}));
      
      assert(isequal(body,body4));
      
      body5 = body.removeCollisionGroupsExcept({'group2','group3'});
      body6 = body.removeCollisionGroupsExcept({'group1','group3'});
      body7 = body.removeCollisionGroupsExcept({'group1'});
      
      assert(isequal(body7.contact_shapes,{shape1, shape4}));
      assert(isequal(body7.contact_shape_group_name,{'group1'}));
      assert(isequal(body7.contact_shape_group,{[1 2]}));
      
      assert(isequal(body2,body5));
      assert(isequal(body3,body6));
      
    end
    
    function testMakeBelongToCollisionFilterGroup
      body = RigidBody();
      collision_fg_id = uint16(3);
      belongs_to_ref = '0000000000000101';
      body = makeBelongToCollisionFilterGroup(body,collision_fg_id);
      belongs_to = dec2bin(body.collision_filter.belongs_to,16);
      assert(strcmp(belongs_to,belongs_to_ref), ...
      'Expected ''%s'', found ''%s''',belongs_to_ref,belongs_to);
    end

    function testMakeIgnoreCollisionFilterGroup
      body = RigidBody();
      collision_fg_id = uint16(3);
      collides_with_ref = '1111111111111011';
      body = makeIgnoreCollisionFilterGroup(body,collision_fg_id);
      collides_with = dec2bin(body.collision_filter.collides_with,16);
      assert(strcmp(collides_with,collides_with_ref), ...
      'Expected ''%s'', found ''%s''',collides_with_ref,collides_with);
    end

    function testMakeBelongToNoCollisionFilterGroups
      body = RigidBody();
      collision_fg_id = uint16(3);
      belongs_to_ref = '0000000000000000';
      body = makeBelongToCollisionFilterGroup(body,collision_fg_id);
      body = makeBelongToNoCollisionFilterGroups(body);
      belongs_to = dec2bin(body.collision_filter.belongs_to,16);
      assert(strcmp(belongs_to,belongs_to_ref), ...
      'Expected ''%s'', found ''%s''',belongs_to_ref,belongs_to);
    end

    function testMakeIgnoreNoCollisionFilterGroups
      body = RigidBody();
      collision_fg_id = uint16(3);
      collides_with_ref = '1111111111111111';
      body = makeIgnoreCollisionFilterGroup(body,collision_fg_id);
      body = makeIgnoreNoCollisionFilterGroups(body);
      collides_with = dec2bin(body.collision_filter.collides_with,16);
      assert(strcmp(collides_with,collides_with_ref), ...
      'Expected ''%s'', found ''%s''',collides_with_ref,collides_with);
    end
  end
  
  methods    
    function obj = updateBodyIndices(obj,map_from_old_to_new)
      obj.parent = map_from_old_to_new(obj.parent);
    end
  end
end
