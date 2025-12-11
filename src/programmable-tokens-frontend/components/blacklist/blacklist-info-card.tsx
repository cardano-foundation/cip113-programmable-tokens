"use client";

import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Shield, AlertTriangle, Lock, Unlock, FileCheck } from 'lucide-react';

interface BlacklistInfoCardProps {
  title: string;
  description: string;
  features: string[];
  icon: 'shield' | 'alert' | 'lock' | 'unlock' | 'file';
}

export function BlacklistInfoCard({ title, description, features, icon }: BlacklistInfoCardProps) {
  const icons = {
    shield: Shield,
    alert: AlertTriangle,
    lock: Lock,
    unlock: Unlock,
    file: FileCheck,
  };
  const Icon = icons[icon];

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Icon className="w-5 h-5 text-primary-400" />
          {title}
        </CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="space-y-2">
          {features.map((feature, index) => (
            <li key={index} className="flex items-start gap-2 text-sm text-dark-300">
              <span className="w-1.5 h-1.5 rounded-full bg-primary-400 mt-2 flex-shrink-0" />
              {feature}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
