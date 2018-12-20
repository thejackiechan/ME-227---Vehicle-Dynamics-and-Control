%% ME227 Nonlinear Simulation 
%  Vehicle Tracking a Path
clear;
clc;
close all;

% path for testing
% s = 0:0.25:120; % straight path
% k = zeros(length(s),1);
% path = generate_path(s,k,[0;0;0]);
% path.s_m = s;
% path.k_1pm = k;
% 
% [vx_prof, ax_prof] = tracking_controller_test(path);

% Get our velocity profiles, 
load('project_data.mat');
[vx_prof, ax_prof] = tracking(path);
% % 
% % %add it to our path struct
path.ux_des = vx_prof;
path.ax_des = ax_prof;

figure(1); ax(2) = subplot(2,1,1); plot(path.s_m,path.ax_des); title('Desired Longitudinal Acceleration');
ylabel('Forward Acceleration [m/sec^2]');
xlabel('Distance along path');
figure(1);ax(1) = subplot(2,1,2); plot(path.s_m,path.ux_des);  title('Desired Longitudinal Velocity');
ylabel('Forward Velocity [m/sec]');
linkaxes(ax,'x');
xlabel('Distance along path');

% path for project

%% Bunch of constants
C_alphaf = 275000; %N/rad
C_alphar = 265000; %N/rad
u_f = 0.97;
u_fs = 0.97;
u_r = 1.03;
u_rs = 1.03;
m = 1659; % kg 
Iz = 2447; % kg m2
L = 2.468; % m
percent_front = .577;
percent_rear = .423;

f_rr = 0.0157;
C_DA = 0.594;

%(1)
g = 9.8;
Fx_total = 0.3*m*g;
ux_diff = 1;
k_vel = Fx_total/ux_diff;

e0 = 0;
ux0 = 3;

g = 9.8;
a = percent_rear*L;
b = percent_front*L;

% integrate s and k with given initial conditions [psi0, E0, N0] to get path
Fz_front = m*g*percent_front;
Fz_rear = m*g*percent_rear;
alpha_sl_front = abs(atand(3*u_f*Fz_front/C_alphaf));
alpha_sl_rear = abs(atand(3*u_r*Fz_rear/C_alphar));

%%  simulation time
dT = 0.005;
t_final = 41;
t_s = 0:dT:t_final;
N = length(t_s);

% allocate space for simulation data
ux_mps = zeros(N,1);
ux_dot = zeros(N,1);
uy_mps = zeros(N,1);
uy_dot = zeros(N,1);
r_radps = zeros(N,1);
s_m = zeros(N,1);
e_m = zeros(N,1);
delta_psi_rad = zeros(N,1);
Fx_total = zeros(N,1);
delta_steer = zeros(N,1);
ux_dot_mps = zeros(N,1);

% set initial conditions
ux_mps(1) = ux0;
uy_mps(1) = 0;
r_radps(1)  = 0;
s_m(1) = 0;
e_m(1) = e0;
delta_psi_rad(1) = 0;
ux_dot_mps(1) = 0;


%Nonlinear model
% simulation loop
for idx = 1:N
    % look up K
    k = interp1(path.s_m, path.k_1pm, s_m(idx));
    
    % current states
    ux = ux_mps(idx);
%       if(ux < .01) % magic minimum speed
%           ux = .01;
%       end

    uy = uy_mps(idx);
    r = r_radps(idx);
    e = e_m(idx);
    s = s_m(idx);
    delta_psi = delta_psi_rad(idx);
   %% Disturbance on lateral error
    lower_lim = -0.0002;
    upper_lim = 0.0002; % constant de error
    de = lower_lim + (upper_lim-lower_lim).*rand(1,1);

    %% Disturbance on ux 
    lower_lim = -0.05;
    upper_lim = 0.05; % constant de error
    dUx = lower_lim + (upper_lim-lower_lim).*rand(1,1);
    %dUx= 0;
    
%% CALL TO ME227 CONTROLLER
    [delta_steer, Fx_total] = me227_controller(s, (e+de), delta_psi, (ux+dUx), uy, r, 2, path);

    rad2deg(delta_steer);
    alpha_f = rad2deg(atan(((uy + a*r)/ux)) - delta_steer);
    alpha_r = rad2deg(atan((uy - b*r)/ux));
    F_yf = proj_calculateFy(alpha_sl_front, C_alphaf, alpha_f, u_f, u_fs, Fz_front);
    F_yr = proj_calculateFy(alpha_sl_rear, C_alphar, alpha_r, u_r, u_rs, Fz_rear);
    
    % drag force
    air_density = 1.225;
    F_d = 0.5 * air_density * ux^2 * C_DA;
    accel_drag = F_d/m;
    
    % rolling resistance 
    F_rr = f_rr * m * g;
    a_rr = F_rr/m;
    
    % control input
    Fg = 0; %not given grade
    
    % Longitudinal Forces
    F_xf = Fx_total * 0.6;
    F_xr = Fx_total * 0.4;
    
    % equations of motion
    ux_dot(idx) = ((F_xr + F_xf*cos(delta_steer) - F_yf*sin(delta_steer))/m) + ...
        r*uy - accel_drag - a_rr;
    uy_dot(idx) = ((F_yf*cos(delta_steer) + F_yr +F_xf*sin(delta_steer))/m) - r*ux;
    r_dot = (a*F_yf*cos(delta_steer) + a*F_xf*sin(delta_steer) -  b*F_yr)/Iz;
    
    s_dot = (1/(1-e*k))*(ux*cos(delta_psi) - uy*sin(delta_psi));
    e_dot = uy*cos(delta_psi) + ux*sin(delta_psi);
    delta_psi_dot = r - k*s_dot;

    % only update next state if we are not at end of simulation
    if idx < N
        % euler integration
        ux_mps(idx+1) = ux_mps(idx) + ux_dot(idx)*dT;
        uy_mps(idx+1) = uy_mps(idx) + uy_dot(idx)*dT;
        r_radps(idx+1) = r_radps(idx) + r_dot*dT;
        s_m(idx+1) = s_m(idx) + s_dot*dT;
        e_m(idx+1) = e_m(idx) + e_dot*dT;
        delta_psi_rad(idx+1) = delta_psi_rad(idx) + delta_psi_dot*dT;
    end
end
% figure
% plot(t_s, ux_mps);
% title('ux vs time');
% figure()
% plot(t_s, e_m)
% title('lateral error vs. time');
% figure
% plot(t_s, ux_mps)
% title('Longitudinal Speed vs Time')
% figure
% ax = ux_dot - r_radps.*uy_mps;
% plot(t_s, ax);
% title('ax_acceleration');
% figure
% ay = uy_dot + r_radps.*ux_dot;
% plot(t_s, ay);
% title('ay_acceleration');
% 
% figure
% amax = sqrt(ay.^2+ax.^2);
% plot(t_s, amax);
% title('Max allowable Accelerations');
% 
% figure(1); ax(2) = subplot(2,1,1); plot(t_s, ax); title('ax_car');
% figure(1);ax(1) = subplot(2,1,2); plot(t_s, ux_mps); title('vx_d');
% linkaxes(ax,'x');

plot(t_s, e_m)
hold on
load('processed_pole_2018-05-13_ae.mat')
plot(t, e_m)
legend('e_m simulation', 'e_m actual');

