function runValueIteration

plant = PendulumPlant;
options.dt = 1e-2;
options.gamma = .999;
options.wrap_flag = [true;false];
%cost = @mintime; ulimit = 1;
cost = @lqrcost; ulimit = 5;
xbins = {linspace(0,2*pi,51),linspace(-10,10,51)};
mdp = MarkovDecisionProcess.discretizeSystem(plant,cost,xbins,linspace(-ulimit,ulimit,9),options);

function drawfun(J,PI)
  figure(2); clf;
  n1=length(xbins{1});
  n2=length(xbins{2});
  subplot(2,1,1);imagesc(xbins{1},xbins{2},reshape(PI,n1,n2)');
  axis xy;
  xlabel('theta');
  ylabel('thetadot');
  title('u(x)');
  subplot(2,1,2);imagesc(xbins{1},xbins{2},reshape(J,n1,n2)');
  axis xy;
  xlabel('theta');
  ylabel('thetadot');
  title('J(x)');
  drawnow;
end

valueIteration(mdp,0.001,@drawfun);

end

function g = lqrcost(sys,x,u)
  xd = [pi;0];
  g = (x-xd)'*(x-xd) + u^2;
end

function g = mintime(sys,x,u)
  xd = [pi;0];
  if (x-xd)'*(x-xd) < .05;
    g = 0;
  else
    g = 1;
  end
end
