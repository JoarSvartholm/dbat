function [x,code,n,r,J,T,rr,lambdas]=levenberg_marquardt(...
    resFun,vetoFun,x0,maxIter,convTol,doTrace,lambda0,lambdaMin,params);
%LEVENBERG_MARQUARDT Levenberg-Marquardt least squares adjustment algorithm.
%
%   [X,CODE,I]=LEVENBERG_MARQUARDT(RES,VETO,X0,N,TOL,TRACE,L0,MINL,PARAMS)
%   runs the Levenberg-Marquardt least squares adjustment algorithm on the
%   problem with residual function RES and with initial values X0. A maximum
%   of N iterations are allowed and the convergence tolerance is TOL. The
%   final estimate is returned in X. The damping algorithm uses L0 as the
%   initial lambda value. Any lambda value below MINL is considered to be
%   zero. In addition, if supplied and non-empty, the VETO function is
%   called to verify that the suggested trial point is not invalid. The
%   number of iteration I and a success code (0 - OK, -1 - too many
%   iterations, -2 - matrix is singular) are also returned. If TRACE is
%   true, output sigma0 estimates at each iteration.
%
%   If the supplied L0 is negative, the initial lambda is calculated as
%   abs(L0)*trace(J0'*J0)/NN, where J0 is the Jacobian of the residual
%   function evaluated at X0, and NN is the number of unknowns. The same
%   applies for MINL.
%
%   [X,CODE,I,F,J]=... also returns the final estimates of the residual
%   vector F and Jacobian matrix J.
%
%   [X,CODE,I,F,J,T,RR,LAMBDAS]=... returns the iteration trace as
%   successive columns in T, the successive estimates of sigma0 in RR and
%   the used damping values in LAMBDAS.
%
%   The function RES is assumed to return the residual function and its
%   jacobian when called [F,J]=feval(RES,X0,PARAMS{:}), where the cell array
%   PARAMS contains any extra parameters for the residual function.
%
%   References:
%     Börlin, Grussenmeyer (2013), "Bundle Adjustment With and Without
%       Damping". Photogrammetric Record 28(144), pp. 396-415. DOI
%       10.1111/phor.12037.
%     Nocedal, Wright (2006), "Numerical Optimization", 2nd ed.
%       Springer. ISBN 978-0-387-40065-5.
%     Levenberg (1944), "A method for the solution of certain nonlinear
%       problems in least squares", Quarterly Journal of Applied
%       Mathematics, 2(2):164-168.
%     Marquardt (1963), "An algorithm for least squares estimation of
%       nonlinear parameters", SIAM Journal on Applied Mathematics,
%       11(2):431-441.
%
%See also: BUNDLE, GAUSS_MARKOV, GAUSS_NEWTON_ARMIJO,
%   LEVENBERG_MARQUARDT_POWELL.

% $Id$

% Initialize current estimate and iteration trace.
x=x0;

if nargout>5
    % Pre-allocate fixed block if trace is asked for.
    blockSize=50;
    T=nan(length(x),min(blockSize,maxIter+1));
end

% Iteration counter.
n=0;

% OK until signalled otherwise.
code=0;

% Compute initial residual and Jacobian.
[r,J]=feval(resFun,x,params{:});
f=1/2*r'*r;
JTJ=J'*J;
JTr=J'*r;

% Residual norm trace.
rr=[];

% Compute real lambda0 if asked for.
if lambda0<0
    lambda0=abs(lambda0)*trace(JTJ)/size(J,2);
end

% Ditto for lambdaMin.
if lambdaMin<0
    lambdaMin=abs(lambdaMin)*trace(JTJ)/size(J,2);
end

% Initialize the damping parameter.
lambda=lambda0;

% Set to zero if below threshold.
if lambda<lambdaMin
    lambda=0;
end

% Store it.
lambdas=lambda;

% Damping from last successful step.
prevLambda=nan;

% Damping matrix.
I=speye(size(J,2));

if doTrace
end

while true
    % Stay in inner loop until a  better point is found or we run out of
    % iterations.
    while n<=maxIter
        % Solve for update p.
        p=(JTJ+lambda*I)\(-JTr);
        
        % Store current residual norm and used lambda value.
        rr(end+1)=sqrt(r'*r);
        lambdas(end+1)=lambda;

        if doTrace
            if n==0
                fprintf(['Levenberg-Marquardt: iteration %d, ',...
                         'residual norm=%.2g\n'],n,rr(end));
            else
                fprintf(['Levenberg-Marquardt: iteration %d, ', ...
                         'residual norm=%.2g, lambda=%.2g\n'],n,rr(end),...
                        lambda);
            end
        end
    
        if nargout>5
            % Store iteration trace.
            if n+1>size(T,2)
                % Expand by blocksize if needed.
                T=[T,nan(length(x),blockSize)]; %#ok<AGROW>
            end
            T(:,n+1)=x;
        end

        % Update iteration count.
        n=n+1;
        
        % Pre-calculate J*p.
        Jp=J*p;

        % Compute residual and objective function value at trial point.
        t=x+p;
        rNew=feval(resFun,t,params{:});
        fNew=1/2*rNew'*rNew;
        
        if fNew<f && ~isempty(vetoFun)
            % Call veto function only if we have a better point.
            fail=feval(vetoFun,t,params{:});
        else
            fail=false;
        end

        if fNew<f && ~fail
            % Good step, accept it.
            x=t;
            % Decrease damping in next iteration.
            lambda=lambda/10;
            % Switch to undamped if damping is small enough.
            if lambda<lambdaMin
                lambda=0;
            end

            % Evaluate residual, Jacobian, and objective function at new
            % point.
            [r,J]=feval(resFun,x,params{:});
            f=1/2*r'*r;
            JTJ=J'*J;
            JTr=J'*r;
            
            % Leave inner loop since we found a better point.
            break;
        else
            % Bad step, discard t and increase damping.
            if lambda==0
                % Switch from undamped to minimum damping.
                lambda=lambdaMin;
            else
                lambda=lambda*10;
            end
        end
    end

    % We have either found a better point or run out of iterations.
    
    % Terminate with success if last step was without damping and we
    % satisfy the termination criteria.
    if prevLambda==0 && norm(Jp)<convTol*norm(r)
        break;
    end
    
    % Remember lambda from last successful step.
    prevLambda=lambda;
    
    if n>maxIter
        code=-1; % Too many iterations.
        break;
    end
    
end

if nargout>5
    % Store final point.
    if n+1>size(T,2)
        % Expand by blocksize if needed.
        T=[T,nan(length(x),blockSize)]; %#ok<AGROW>
    end
    T(:,n+1)=x;
end

rr(end+1)=sqrt(r'*r);

% Trim unused trace columns.
if nargout>5
    T=T(:,1:n+1);
end
